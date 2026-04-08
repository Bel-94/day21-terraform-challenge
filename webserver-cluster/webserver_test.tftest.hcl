# webserver_test.tftest.hcl — Day 21
# Tests run with: terraform test
# All tests use command = plan (no AWS credentials needed, no real resources created)

mock_provider "aws" {}

variables {
  cluster_name        = "test-cluster-day21"
  instance_type       = "t2.micro"
  min_size            = 1
  max_size            = 2
  environment         = "dev"
  app_version         = "v4"
  cpu_alarm_threshold = 80
  cpu_low_threshold   = 20
}

# ── Existing resource tests (regression) ──────────────────────────────────────

run "validate_asg_name_prefix" {
  command = plan

  assert {
    condition     = aws_autoscaling_group.this.name_prefix == "test-cluster-day21-asg-"
    error_message = "ASG name_prefix must be {cluster_name}-asg-"
  }
}

run "validate_instance_type" {
  command = plan

  assert {
    condition     = aws_launch_template.this.instance_type == "t2.micro"
    error_message = "Launch template instance_type must match var.instance_type"
  }
}

run "validate_health_check_type" {
  command = plan

  assert {
    condition     = aws_autoscaling_group.this.health_check_type == "ELB"
    error_message = "ASG must use ELB health checks, not EC2"
  }
}

run "validate_alb_sg_port" {
  command = plan

  assert {
    condition     = one(aws_security_group.alb.ingress).from_port == 80
    error_message = "ALB security group must allow port 80 inbound"
  }
}

run "validate_environment_tag" {
  command = plan

  assert {
    condition = anytrue([
      for tag in aws_autoscaling_group.this.tag :
      tag.key == "Environment" && tag.value == "dev" && tag.propagate_at_launch == true
    ])
    error_message = "Environment tag must propagate to instances"
  }
}

# ── New Day 21 alarm tests ─────────────────────────────────────────────────────

run "validate_high_cpu_alarm_name" {
  command = plan

  assert {
    condition     = aws_cloudwatch_metric_alarm.high_cpu.alarm_name == "test-cluster-day21-high-cpu"
    error_message = "High-CPU alarm name must be {cluster_name}-high-cpu"
  }
}

run "validate_high_cpu_alarm_threshold" {
  command = plan

  assert {
    condition     = aws_cloudwatch_metric_alarm.high_cpu.threshold == 80
    error_message = "High-CPU alarm threshold must match var.cpu_alarm_threshold"
  }
}

run "validate_high_cpu_alarm_operator" {
  command = plan

  assert {
    condition     = aws_cloudwatch_metric_alarm.high_cpu.comparison_operator == "GreaterThanThreshold"
    error_message = "High-CPU alarm must use GreaterThanThreshold"
  }
}

run "validate_low_cpu_alarm_name" {
  command = plan

  assert {
    condition     = aws_cloudwatch_metric_alarm.low_cpu.alarm_name == "test-cluster-day21-low-cpu"
    error_message = "Low-CPU alarm name must be {cluster_name}-low-cpu"
  }
}

run "validate_low_cpu_alarm_threshold" {
  command = plan

  assert {
    condition     = aws_cloudwatch_metric_alarm.low_cpu.threshold == 20
    error_message = "Low-CPU alarm threshold must match var.cpu_low_threshold"
  }
}

run "validate_low_cpu_alarm_operator" {
  command = plan

  assert {
    condition     = aws_cloudwatch_metric_alarm.low_cpu.comparison_operator == "LessThanThreshold"
    error_message = "Low-CPU alarm must use LessThanThreshold"
  }
}

run "validate_unhealthy_hosts_alarm" {
  command = plan

  assert {
    condition     = aws_cloudwatch_metric_alarm.unhealthy_hosts.threshold == 0
    error_message = "Unhealthy-hosts alarm threshold must be 0"
  }
}

run "validate_sns_topic_name" {
  command = plan

  assert {
    condition     = aws_sns_topic.alerts.name == "test-cluster-day21-alerts"
    error_message = "SNS topic name must be {cluster_name}-alerts"
  }
}

# ── Validation rejection tests ─────────────────────────────────────────────────

run "reject_invalid_environment" {
  command = plan

  variables {
    environment = "sandbox"
  }

  expect_failures = [var.environment]
}

run "reject_invalid_instance_type" {
  command = plan

  variables {
    instance_type = "m5.large"
  }

  expect_failures = [var.instance_type]
}
