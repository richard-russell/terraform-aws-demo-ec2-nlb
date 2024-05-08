
# Test file with mock provider.
# - all AWS resources are mock
# - need to define ARN-like outputs to pass tests

mock_provider "aws" {
  mock_resource "aws_lb" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:fk-region-1:111111111111:loadbalancer/net/fakename/123"
    }
  }
  mock_resource "aws_lb_target_group" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:fk-region-1:111111111111:loadbalancer/net/fakename/123"
    }
  }
}

mock_provider "http" {
  mock_data "http" {
    defaults = {
       status_code = 200
    }
  }
}

variables {
  service_name = "test-service"
  env = "test-env"
}

run "integration" {}

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