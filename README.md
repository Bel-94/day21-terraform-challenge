# Day 21 — Workflow for Deploying Infrastructure Code

## Directory Structure

```
day_21/
├── .github/workflows/
│   └── terraform-workflow.yml   # CI: lint - unit tests
├── sentinel/
│   ├── require-instance-type.sentinel
│   └── sentinel.hcl
├── webserver-cluster/
│   ├── backend.tf
│   ├── main.tf                  # KEY CHANGE: new low_cpu alarm + asg_name output
│   ├── outputs.tf
│   ├── variables.tf
│   ├── webserver_test.tftest.hcl
│   └── scripts/
│       └── user-data.sh
├── images/
├── PR_DESCRIPTION.md
└── README.md
```

---

## The Full Seven-Step Walkthrough

### Step 1 — Version Control

A dedicated GitHub repository was created for Day 21. Branch protection was configured on `main` using GitHub's Rulesets:

- Require a pull request before merging
- Block force pushes to main
- No direct pushes allowed

All infrastructure changes travel through a feature branch - PR - CI - merge workflow. No commits land directly on `main`.

```bash
# Always confirm you are on a feature branch, never on main
git branch
# Expected: * add-cloudwatch-alarms-day21
```

---

### Step 2 — Run the Code Locally (terraform plan)

Before making any change, `terraform plan` was run against the existing state to establish a clean baseline.

```bash
cd webserver-cluster

# Authenticate with Terraform Cloud
terraform login

# Initialise — downloads providers, connects to TFC backend
terraform init

# Generate and save the plan — ALWAYS save to a file
terraform plan -out day21.tfplan
```

![terraform init and plan](images/terraform-init-hecp-terraform.png)

![terraform plan output](images/terraform-plan.png)

The plan showed exactly what was expected:
```
Plan: 1 to add, 0 to change, 0 to destroy.
Changes to Outputs:
  + asg_name = (known after apply)
```

> The plan file is saved to `day21.tfplan`. This binary file is never committed to Git, it is applied exactly as reviewed in Step 7.

---

### Step 3 — Make Code Changes on a Feature Branch

The infrastructure change for Day 21:
- **New resource:** `aws_cloudwatch_metric_alarm.low_cpu` — fires when average CPU stays below 20% for 6 minutes (scale-in signal)
- **New variable:** `cpu_low_threshold` (default: 20)
- **New outputs:** `asg_name`, `cloudwatch_alarms`

```bash
# Create the feature branch
git checkout -b add-cloudwatch-alarms-day21

# Stage and commit the changes
git add .
git commit -m "Add low-CPU alarm and asg_name output for webserver cluster"
git push origin add-cloudwatch-alarms-day21
```

The key addition in `main.tf`:

```hcl
# NEW in Day 21 — low-CPU alarm (scale-in signal)
resource "aws_cloudwatch_metric_alarm" "low_cpu" {
  alarm_name          = "${var.cluster_name}-low-cpu"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = var.cpu_low_threshold
  alarm_description   = "Fires when average CPU stays below ${var.cpu_low_threshold}% for 6 minutes"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.this.name
  }
}
```

---

### Step 4 — Submit for Review (Pull Request)

A PR was opened from `add-cloudwatch-alarms-day21` - `main`. The PR description included the full plan output, blast radius assessment, and rollback plan so the reviewer could understand exactly what would change in AWS without running Terraform themselves.

**PR template used:**

```
## What this changes
Add a low-CPU CloudWatch alarm and asg_name output.

## Terraform plan output
Plan: 1 to add, 0 to change, 0 to destroy.

## Resources affected
- Created: 1 (aws_cloudwatch_metric_alarm.low_cpu)
- Modified: 0
- Destroyed: 0

## Blast radius
Additive only no shared infrastructure touched.

## Rollback plan
terraform destroy -target=aws_cloudwatch_metric_alarm.low_cpu
```

---

### Step 5 — Run Automated Tests

The GitHub Actions workflow ran automatically on PR open with two jobs:

**Job 1 — lint** (no AWS credentials needed):
```bash
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
```

**Job 2 — unit-tests** (no AWS credentials needed):
```bash
terraform init -backend=false
terraform test
# 15 assertions in webserver_test.tftest.hcl
# All use mock_provider "aws" {} — zero real resources created
```

![CI lint and unit tests passed](images/lint-unittests-passed.png)

Both jobs green; PR eligible for merge.

**Challenges encountered and fixed:**
- `terraform fmt -check` failed on `outputs.tf` due to misaligned map keys, fixed by running `terraform fmt` locally
- `terraform test` failed with "No valid credential sources found"  fixed by adding `mock_provider "aws" {}` to the test file, which tells the test runner to use a fake provider instead of authenticating with real AWS

To run tests locally:
```bash
cd webserver-cluster
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
terraform test
```

![Local tests passing](images/local-tests-passed.png)

Expected output:
```
run "validate_asg_name_prefix"... pass
run "validate_instance_type"... pass
run "validate_health_check_type"... pass
run "validate_alb_sg_port"... pass
run "validate_environment_tag"... pass
run "validate_high_cpu_alarm_name"... pass
run "validate_high_cpu_alarm_threshold"... pass
run "validate_high_cpu_alarm_operator"... pass
run "validate_low_cpu_alarm_name"... pass
run "validate_low_cpu_alarm_threshold"... pass
run "validate_low_cpu_alarm_operator"... pass
run "validate_unhealthy_hosts_alarm"... pass
run "validate_sns_topic_name"... pass
run "reject_invalid_environment"... pass
run "reject_invalid_instance_type"... pass
15 tests, 0 failures
```

---

### Step 6 — Merge and Tag

With CI green the PR was merged into `main`.

![Ready to merge after tests passed](images/ready-to-merge-after-tests-passed.png)

The new module version was tagged immediately after merge:

```bash
git checkout main
git pull origin main
git tag -a "v1.5.0" -m "Add low-CPU alarm and asg_name output for webserver cluster"
git push origin v1.5.0
```

![Tag on main branch](images/tag-main-branch.png)

---

### Step 7 — Deploy (Apply the Saved Plan)

The saved plan file from Step 2 was applied  exactly what was reviewed, nothing more:

```bash
cd webserver-cluster
terraform apply day21.tfplan
```

![terraform apply terminal output](images/terraform-apply-terminal.png)

![terraform apply in Terraform Cloud](images/terraform-apply-terraform-cloud.png)

**Post-apply verification:**

```bash
# 1. Confirm all three alarms exist
aws cloudwatch describe-alarms \
  --alarm-name-prefix "belinda-day21" \
  --query 'MetricAlarms[*].{Name:AlarmName,State:StateValue}' \
  --output table
```

![All 3 alarms confirmed in CloudWatch](images/Confirm-all-3-alarms-exist.png)

```bash
# 2. Confirm plan is clean — no drift
terraform plan -detailed-exitcode
# Exit code 0 = state matches reality
```

![Plan is clean after apply — no drift](images/plan-is-clean-no-drift.png)

```bash
# 3. Confirm outputs
terraform output asg_name
terraform output cloudwatch_alarms
```

![Outputs confirmed](images/confirm-outputs.png)

---

## Infrastructure-Specific Safeguards

### 1. Approval Gates for Destructive Changes

In Terraform Cloud, manual apply mode was enabled:
- Workspace - Settings - General - Apply Method - **Manual apply**
- Any plan showing `destroy` lines requires explicit confirmation before apply proceeds

If `terraform plan` shows any destruction, stop get sign-off from a second engineer before applying.

### 2. Plan File Pinning

```bash
# CORRECT — apply exactly what was reviewed
terraform plan -out day21.tfplan
terraform apply day21.tfplan

# RISKY — never do this; generates a fresh plan at apply time
# terraform apply
```

The gap between `terraform plan` and `terraform apply` can be minutes or hours. If another engineer applies a change in that window, your apply operates on different state than what was reviewed. The reviewed plan is no longer accurate.

### 3. State Backup Before Apply

State is stored in Terraform Cloud with full version history. Before any significant apply, verify versioning:

```bash
aws s3api get-bucket-versioning \
  --bucket belinda-terraform-state-30daychallenge \
  --query 'Status'
# Expected: "Enabled"
```

To restore a previous state version:
```bash
aws s3api list-object-versions \
  --bucket belinda-terraform-state-30daychallenge \
  --prefix day21/webserver-cluster/terraform.tfstate \
  --query 'Versions[*].{VersionId:VersionId,LastModified:LastModified}' \
  --output table

aws s3api get-object \
  --bucket belinda-terraform-state-30daychallenge \
  --key day21/webserver-cluster/terraform.tfstate \
  --version-id <VersionId> \
  terraform.tfstate.restored
```

### 4. Blast Radius Documentation

Every PR touching shared infrastructure must document what breaks if the apply fails midway. This PR's blast radius was **minimal** — the new alarm is additive only and scoped to this ASG. No VPCs, security groups, or IAM roles were modified.

---

## Sentinel Policy

File: `sentinel/require-instance-type.sentinel`

### What it enforces

Every `aws_instance` and `aws_launch_template` in the plan must use an instance type from the approved list:

```
t2.micro  t2.small  t2.medium  t3.micro  t3.small  t3.medium
```

### What it blocks vs allows

```hcl
# BLOCKED — m5.large is not in the approved list
resource "aws_launch_template" "this" {
  instance_type = "m5.large"
}

# ALLOWED — t2.micro is in the approved list
resource "aws_launch_template" "this" {
  instance_type = "t2.micro"
}
```

### How it differs from terraform validate

| | `terraform validate` | Sentinel |
|---|---|---|
| When it runs | Before plan, locally | After plan, in Terraform Cloud |
| What it checks | Syntax and type correctness | Actual planned values |
| Can enforce business rules | No | Yes |
| Can check instance_type values | No | Yes |
| Scope | Single workspace | Entire organisation |

`terraform validate` passes `instance_type = "m5.large"` because it is syntactically valid HCL. Sentinel blocks it because the actual value violates the cost policy. This is the critical difference — Sentinel operates on what Terraform *will do*, not just whether the code is valid.

### Connecting Sentinel to Terraform Cloud

1. Push the `sentinel/` directory to GitHub
2. Terraform Cloud - Settings - Policy Sets - Connect a new policy set
3. Select the repo, set path to `sentinel/`
4. Apply the policy set to your workspace
5. Every plan now runs through Sentinel before apply is permitted

> Note: Sentinel requires Terraform Cloud Plus or Business tier. On free/trial tiers, set `enforcement_level = "advisory"` in `sentinel.hcl` to log warnings without blocking applies.

---

## Infrastructure vs Application Workflow — Key Differences

### 1. State files have no application equivalent

Infrastructure deployments operate against a state file that records what currently exists in AWS. If two engineers run `terraform apply` simultaneously, they corrupt each other's state. A bad application deploy returns a 500 error. A bad infrastructure deploy can delete a production database.

**Why it matters:** State locking and plan file pinning exist specifically because of this risk. Application CI/CD has no equivalent safeguard.

### 2. Blast radius is asymmetric

A bad application deploy affects that application only. A bad infrastructure deploy can affect every application that depends on the changed resource — modifying a shared security group or VPC can break dozens of services simultaneously.

**Why it matters:** Infrastructure PRs require explicit blast radius documentation. Application PRs do not, because the failure domain is bounded by the application itself.

### 3. Rollback is not always possible

Application rollback means redeploy the previous version. Infrastructure rollback can be impossible, you cannot un-delete a database, un-rotate a secret, or recover an EC2 instance that held in-memory state. Some infrastructure changes are one-way doors.

**Why it matters:** Approval gates for destructive changes exist because `terraform destroy` on a production database cannot be undone by redeploying the previous Docker image.

---

## Chapter 10 Learnings

**Most dangerous step:** The author identifies `terraform apply` as the most dangerous step; specifically the gap between `plan` and `apply`. If infrastructure changes between the two (another engineer applies, a resource is modified manually, drift occurs), the apply operates on different state than what was reviewed. The reviewed plan is no longer accurate.

**Safeguard most teams skip:** Saving the plan to a file and applying from that exact file:
```bash
terraform plan -out=reviewed.tfplan
terraform apply reviewed.tfplan
```
Most teams run `terraform apply` directly, which generates a fresh plan at apply time. This means the apply can differ from what was reviewed — defeating the entire purpose of the review step.

---

## Cleanup

After verifying all outputs and confirming the plan was clean, the infrastructure was destroyed to avoid ongoing AWS costs:

```bash
terraform destroy
```

![Destroy running in Terraform Cloud](images/destroy-running-on-terraform-cloud.png)

![Destroy successful](images/destroy-successful.png)

---

## Challenges and Fixes

**`terraform fmt -check` failed in CI:** `outputs.tf` had misaligned map keys. Fixed by running `terraform fmt -recursive` locally before pushing.

**`terraform test` failed with AWS credential error:** The test runner tried to initialise the real AWS provider even with `-backend=false`. Fixed by adding `mock_provider "aws" {}` at the top of `webserver_test.tftest.hcl` — this replaces the real provider with a fake one so no credentials are needed.

**Sentinel on free tier:** Sentinel policy enforcement requires Terraform Cloud Plus. On the free tier, `enforcement_level = "advisory"` is used so the policy runs and logs results without blocking applies.

**Plan file is a binary:** `day21.tfplan` must never be committed to Git — it contains state references and is only valid for the state version it was generated against. It is listed in `.gitignore`.

---

## Let's Connect

If this walkthrough helped you understand infrastructure deployment workflows, I'd love to hear from you. Follow along as I work through all 30 days of the Terraform Challenge, there's a new post every day covering real infrastructure, real problems, and real fixes.

- **Blog** — deep dives on every day of the challenge: [medium.com/@ntinyaribelinda](https://medium.com/@ntinyaribelinda)
- **LinkedIn** — connect and follow the journey: [linkedin.com/in/belinda-ntinyari](https://www.linkedin.com/in/belinda-ntinyari/)

> If you're doing the 30-Day Terraform Challenge too, drop a comment on the blog post. I'd love to see what infrastructure changes you deployed through your workflow today.
