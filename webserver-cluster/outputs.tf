output "alb_dns_name" {
  description = "ALB DNS name"
  value       = aws_lb.this.dns_name
}

output "alb_url" {
  description = "Full URL to verify the deployed cluster"
  value       = "http://${aws_lb.this.dns_name}"
}

# NEW in Day 21 — exposes ASG name for ops tooling and dashboards
output "asg_name" {
  description = "Auto Scaling Group name — use for CloudWatch dashboards and scaling policies"
  value       = aws_autoscaling_group.this.name
}

output "sns_topic_arn" {
  description = "SNS topic ARN for alarm notifications"
  value       = aws_sns_topic.alerts.arn
}

output "app_version" {
  description = "The application version currently deployed"
  value       = var.app_version
}

output "cloudwatch_alarms" {
  description = "Names of all CloudWatch alarms managing this cluster"
  value = {
    high_cpu        = aws_cloudwatch_metric_alarm.high_cpu.alarm_name
    low_cpu         = aws_cloudwatch_metric_alarm.low_cpu.alarm_name
    unhealthy_hosts = aws_cloudwatch_metric_alarm.unhealthy_hosts.alarm_name
  }
}

output "verification_commands" {
  description = "Run these after apply to confirm the deployment succeeded"
  value = {
    check_response   = "curl -s http://${aws_lb.this.dns_name}"
    check_alarms     = "aws cloudwatch describe-alarms --alarm-names ${aws_cloudwatch_metric_alarm.high_cpu.alarm_name} ${aws_cloudwatch_metric_alarm.low_cpu.alarm_name} --query 'MetricAlarms[*].{Name:AlarmName,State:StateValue}' --output table"
    check_asg        = "aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names ${aws_autoscaling_group.this.name} --query 'AutoScalingGroups[0].{Min:MinSize,Max:MaxSize,Desired:DesiredCapacity}' --output table"
    clean_plan_check = "terraform plan -detailed-exitcode"
  }
}
