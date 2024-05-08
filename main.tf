
locals {
  service_name = join("-", compact([var.service_name, var.env]))
}

# Networking
# Create a VPC to launch our instances into
resource "aws_vpc" "default" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = local.service_name
  }
}

# Create an internet gateway to give our subnet access to the outside world
resource "aws_internet_gateway" "default" {
  vpc_id = aws_vpc.default.id
}

# Grant the VPC internet access on its main route table
resource "aws_route" "internet_access" {
  route_table_id         = aws_vpc.default.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.default.id
}

resource "aws_subnet" "instance" {
  vpc_id                  = aws_vpc.default.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "eu-west-1a"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "lb" {
  vpc_id                  = aws_vpc.default.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "eu-west-1a"
  map_public_ip_on_launch = true
}

resource "aws_security_group" "instance" {
  name        = "${local.service_name}_instance"
  description = "Instance security group"
  vpc_id      = aws_vpc.default.id

  # SSH access from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP access from anwywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS access from anwywhere
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Launch an Amazon Linux 2 instance
data "aws_ami" "amazon-2" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-ebs"]
  }
  owners = ["amazon"]
}

resource "aws_instance" "webserver" {
  ami           = data.aws_ami.amazon-2.id
  instance_type = "t2.micro"
  key_name      = "KeyVanCleef"

  tags = {
    Name = "${local.service_name} webserver"
  }

  vpc_security_group_ids = [aws_security_group.instance.id]
  subnet_id              = aws_subnet.instance.id

  user_data = <<-EOF
#!/bin/bash -v
yum install -y httpd
echo “Hello World from $(hostname -f)” > /var/www/html/index.html
systemctl start httpd &&  systemctl enable httpd
yum install -y mod_ssl
cd /etc/pki/tls/certs
./make-dummy-cert localhost.crt
sed -i '/SSLCertificateKeyFile \/etc\/pki\/tls\/private\/localhost.key/s/^/#/' /etc/httpd/conf.d/ssl.conf
systemctl restart httpd
EOF
}

# NLB
resource "aws_lb" "lb" {
  name               = local.service_name
  internal           = false
  load_balancer_type = "network"
  subnets            = [aws_subnet.lb.id]
}

# HTTP - port 80
resource "aws_lb_listener" "tcp_http" {
  load_balancer_arn = aws_lb.lb.arn
  port              = "80"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tcp_http.arn
  }
}

resource "aws_lb_target_group" "tcp_http" {
  name     = "${local.service_name}-http"
  port     = 80
  protocol = "TCP"
  vpc_id   = aws_vpc.default.id
}

resource "aws_lb_target_group_attachment" "tcp_http" {
  target_group_arn = aws_lb_target_group.tcp_http.arn
  target_id        = aws_instance.webserver.id
}

output "server_url" {
  value = "http://${aws_instance.webserver.public_ip}"
}

output "lb_url" {
  value = "http://${aws_lb.lb.dns_name}"
}

check "response" {
  data "http" "this" {
    url      = "http://${aws_lb.lb.dns_name}"
    insecure = true

    retry {
      attempts     = 180
      max_delay_ms = 1000
      min_delay_ms = 1000
    }
  }

  assert {
    condition     = data.http.this.status_code == 200
    error_message = "HTTP response is ${data.http.this.status_code}"
  }
}

