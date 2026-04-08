# PR Description Template — Infrastructure Changes
# Copy this into your GitHub PR description for every infrastructure change.

## What this changes

Add a low-CPU CloudWatch alarm (`aws_cloudwatch_metric_alarm.low_cpu`) to the
webserver cluster ASG. This alarm fires when average CPU stays below 20% for
6 minutes, providing a scale-in signal. Also adds `asg_name` as an output
variable so ops tooling can reference the ASG without hardcoding names.

## Terraform plan output

```
Terraform will perform the following actions:

  # aws_cloudwatch_metric_alarm.low_cpu will be created
  + resource "aws_cloudwatch_metric_alarm" "low_cpu" {
      + alarm_name          = "belinda-day21-low-cpu"
      + comparison_operator = "LessThanThreshold"
      + evaluation_periods  = 3
      + metric_name         = "CPUUtilization"
      + namespace           = "AWS/EC2"
      + period              = 120
      + statistic           = "Average"
      + threshold           = 20
      + alarm_description   = "Fires when average CPU stays below 20% for 6 minutes — scale-in signal"
      + alarm_actions       = [(known after apply)]
      + ok_actions          = [(known after apply)]
      + dimensions          = {
          + "AutoScalingGroupName" = (known after apply)
        }
    }

Plan: 1 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + asg_name = (known after apply)
```

## Resources affected

- Created: 1 (`aws_cloudwatch_metric_alarm.low_cpu`)
- Modified: 0
- Destroyed: 0

## Blast radius

This change is additive only — it creates a new CloudWatch alarm and adds an
output. No existing resources are modified or destroyed.

If the apply fails partway through:
- The alarm may not exist → no scale-in signal, but the cluster continues serving traffic normally
- The output will be missing → any downstream automation reading `asg_name` will fail until re-applied
- Rollback: `terraform destroy -target=aws_cloudwatch_metric_alarm.low_cpu` removes the partial resource

Shared infrastructure touched: None. This alarm is scoped to this ASG only.
VPCs, security groups, and IAM roles are not affected.

## Rollback plan

1. If the alarm causes unexpected scale-in events after apply:
   ```
   terraform destroy -target=aws_cloudwatch_metric_alarm.low_cpu
   ```
2. If state is corrupted during apply, restore from S3 versioned state:
   ```
   aws s3api list-object-versions \
     --bucket belinda-terraform-state-30daychallenge \
     --prefix day21/webserver-cluster/terraform.tfstate
   # Then restore the previous version via the S3 console or aws s3api get-object
   ```
3. Revert the feature branch and open a new PR with the revert commit.
