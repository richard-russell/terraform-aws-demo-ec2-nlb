
# Test file with real provider but mock EC2 instance
# - all AWS resources are real except the overridden ones
# - need to override http data source to allow check block to pass

# don't create EC2 instance
override_resource {
  target = aws_instance.webserver
}

# don't create LB target group attachment
# required because there's no EC2 instance to attach to
override_resource {
  target = aws_lb_target_group_attachment.tcp_http
}

variables {
  service_name = "test-service"
  env = "test-env"
}

run "integration" {
  override_data {
    target = data.http.this
    values = {
      status_code = 200
    }
  }
}

# make sure check block fails with status_code != 200
run "test_response_check" {

  override_data {
    target = data.http.this
    values = {
      status_code = 401
    }
  }

  expect_failures = [
    check.response
  ]
}