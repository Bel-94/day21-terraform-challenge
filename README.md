# Day 21 — Workflow for Deploying Infrastructure Code

## Directory Structure

```
day_21/
├── .github/workflows/
│   └── terraform-workflow.yml   # CI: lint → unit tests → integration tests
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
├── PR_DESCRIPTION.md
└── README.md
```

---

## The Full Seven-Step Walkthrough

### Step 1 — Version Control

Verify branch protection on `main`:
- Require at least 1 reviewer approval before merge
- Require status checks (lint + unit-tests) to pass before merge
- Block direct pushes to main

```bash
# Confirm you are on a feature branch, never on main
git branch
# Expected: * add-cloudwatch-alarms-day21
```

GitHub branch protection settings path:
`Settings → Branches → Branch protection rules → main`

---

### Step 2 — Run the Code Locally (terraform plan)

```bash
cd day_21/webserver-cluster

# Authenticate with Terraform Cloud
terraform login

# Initialise (downloads providers, connects to TFC backend)
terraform init

# Generate and save the plan — ALWAYS save to a file
terraform plan -out=day21.tfplan

# Review the plan output carefully:
# - Count resources: to add / to change / to destroy
# - ANY destruction line requires extra scrutiny before proceeding
```

Expected plan output for this change:
```
Plan: 1 to add, 0 to change, 0 to destroy.
Changes to Outputs:
  + asg_name = (known after apply)
```

---

### Step 3 — Make Code Changes on a Feature Branch

```bash
# Create the feature branch
git checkout -b add-cloudwatch-alarms-day21

# The changes are already in main.tf and outputs.tf:
#   - aws_cloudwatch_metric_alarm.low_cpu  (new resource)
#   - variable "cpu_low_threshold"         (new variable)
#   - output "asg_name"                    (new output)
#   - output "cloudwatch_alarms"           (new output)

# Re-run plan on the feature branch to confirm only expected changes
terraform plan -out=day21.tfplan

# Stage and commit
git add .
git commit -m "Add low-CPU alarm and asg_name output for webserver cluster"
git push origin add-cloudwatch-alarms-day21
```

---

### Step 4 — Submit for Review (Pull Request)

Open a PR from `add-cloudwatch-alarms-day21` → `main`.

Paste the full content of `PR_DESCRIPTION.md` into the PR description.
The reviewer must be able to understand exactly what will change in AWS
from the PR alone — without running Terraform themselves.

Key sections the reviewer checks:
1. Plan output — confirms only 1 resource added, 0 destroyed
2. Blast radius — confirms no shared infrastructure is touched
3. Rollback plan — confirms there is a safe revert path

---

### Step 5 — Run Automated Tests

The GitHub Actions workflow (`.github/workflows/terraform-workflow.yml`) runs
automatically when the PR is opened:

**Job 1 — lint** (no AWS needed):
```bash
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
```

**Job 2 — unit-tests** (no AWS needed):
```bash
terraform init -backend=false
terraform test
# Runs all 14 assertions in webserver_test.tftest.hcl
# All use command = plan — zero real resources created
```

Both jobs must be green before the PR is eligible for merge.

To run tests locally before pushing:
```bash
cd day_21/webserver-cluster
terraform init -backend=false
terraform fmt -check
terraform validate
terraform test
```

---

### Step 6 — Merge and Tag

Once approved and CI is green, merge the PR.

Tag the new module version:
```bash
git checkout main
git pull origin main
git tag -a "v1.5.0" -m "Add low-CPU alarm and asg_name output for webserver cluster"
git push origin v1.5.0
```

---

### Step 7 — Deploy (Apply the Saved Plan)

```bash
cd day_21/webserver-cluster

# Apply EXACTLY what was reviewed — never run terraform apply without a plan file
terraform apply day21.tfplan
```

Post-apply verification:
```bash
# 1. Confirm the new alarm exists in CloudWatch
aws cloudwatch describe-alarms \
  --alarm-names "belinda-day21-low-cpu" \
  --query 'MetricAlarms[0].{Name:AlarmName,State:StateValue,Threshold:Threshold}' \
  --output table

# 2. Confirm all three alarms are present
aws cloudwatch describe-alarms \
  --alarm-name-prefix "belinda-day21" \
  --query 'MetricAlarms[*].{Name:AlarmName,State:StateValue}' \
  --output table

# 3. Run plan immediately after apply — must return clean (exit code 0)
terraform plan -detailed-exitcode
# Exit code 0 = no changes = state matches reality

# 4. Confirm the new output is present
terraform output asg_name
terraform output cloudwatch_alarms
```

---

## Infrastructure-Specific Safeguards

### 1. Approval Gates for Destructive Changes

In Terraform Cloud:
- Go to workspace → Settings → General
- Enable "Require confirmation for apply" (manual apply mode)
- For any plan showing destructions: require a second explicit approval
  separate from the PR review

If `terraform plan` shows any `destroy` lines, stop and get explicit
sign-off from a second engineer before applying.

### 2. Plan File Pinning

Always apply from a saved plan file:

```bash
# CORRECT — apply exactly what was reviewed
terraform plan -out=day21.tfplan
# ... reviewer approves the plan output ...
terraform apply day21.tfplan

# RISKY — never do this; the plan may differ from what was reviewed
# terraform apply
```

The gap between `terraform plan` and `terraform apply` can be minutes or
hours. If another engineer applies a change in that window, your apply
will operate on different state than what was reviewed.

### 3. State Backup Before Apply

Verify S3 state bucket versioning is enabled:
```bash
aws s3api get-bucket-versioning \
  --bucket belinda-terraform-state-30daychallenge \
  --query 'Status'
# Expected: "Enabled"
```

List available state versions (use before any significant apply):
```bash
aws s3api list-object-versions \
  --bucket belinda-terraform-state-30daychallenge \
  --prefix day21/webserver-cluster/terraform.tfstate \
  --query 'Versions[*].{VersionId:VersionId,LastModified:LastModified}' \
  --output table
```

Restore a previous state version if apply corrupts state:
```bash
# Get the VersionId from the list above, then:
aws s3api get-object \
  --bucket belinda-terraform-state-30daychallenge \
  --key day21/webserver-cluster/terraform.tfstate \
  --version-id <VersionId> \
  terraform.tfstate.restored
```

### 4. Blast Radius Documentation

Every PR touching shared infrastructure (VPCs, security groups, IAM roles)
must document:
- What other resources depend on the changed resource
- What breaks if the apply fails midway through
- The rollback path

This PR's blast radius: **minimal** — the new alarm is additive only and
scoped to this ASG. No shared infrastructure is modified.

---

## Sentinel Policy

File: `sentinel/require-instance-type.sentinel`

### What it enforces

Every `aws_instance` and `aws_launch_template` resource in the plan must use
an instance type from this approved list:
`t2.micro`, `t2.small`, `t2.medium`, `t3.micro`, `t3.small`, `t3.medium`

### What it blocks

```hcl
# This plan would be BLOCKED by Sentinel:
resource "aws_launch_template" "this" {
  instance_type = "m5.large"   # not in allowed list → BLOCKED
}

# This plan would be ALLOWED:
resource "aws_launch_template" "this" {
  instance_type = "t2.micro"   # in allowed list → ALLOWED
}
```

### How it differs from terraform validate

| | `terraform validate` | Sentinel |
|---|---|---|
| When it runs | Before plan, locally | After plan, in Terraform Cloud |
| What it checks | Syntax, type correctness | Actual planned values |
| Can enforce business rules | No | Yes |
| Can check instance_type values | No | Yes |
| Scope | Single workspace | Entire organisation |

`terraform validate` would pass `instance_type = "m5.large"` because it is
syntactically valid. Sentinel blocks it because it violates the cost policy.

### Connecting Sentinel to Terraform Cloud

1. Push the `sentinel/` directory to a GitHub repo
2. In Terraform Cloud: Settings → Policy Sets → Connect a new policy set
3. Select the repo and set the path to `sentinel/`
4. Apply the policy set to your workspace
5. Every plan now runs through Sentinel before apply is permitted

---

## Infrastructure vs Application Workflow — Key Differences

### 1. State files have no application equivalent

Infrastructure deployments operate against a state file that records what
currently exists in AWS. If two engineers run `terraform apply` simultaneously,
they corrupt each other's state. Application deployments have no equivalent
shared mutable file — a bad app deploy returns a 500 error; a bad infra deploy
can delete a production database.

**Why it matters:** State locking (via Terraform Cloud or DynamoDB) and plan
file pinning exist specifically because of this risk. Application CI/CD has
no equivalent safeguard.

### 2. Blast radius is asymmetric

A bad application deploy affects the application. A bad infrastructure deploy
can affect every application that depends on the changed resource. Modifying
a shared security group or VPC can break dozens of services simultaneously.

**Why it matters:** Infrastructure PRs require explicit blast radius
documentation. Application PRs do not, because the failure domain is bounded
by the application itself.

### 3. Rollback is not always possible

Application rollback is usually "redeploy the previous version." Infrastructure
rollback can be impossible — you cannot un-delete a database, un-rotate a
secret, or un-replace an EC2 instance that held in-memory state. Some
infrastructure changes are one-way doors.

**Why it matters:** Approval gates for destructive changes exist because
`terraform destroy` on a production database cannot be undone by redeploying
the previous Docker image.

---

## Chapter 10 Learnings

**Most dangerous step:** The author identifies the `terraform apply` step as
the most dangerous — specifically the gap between `plan` and `apply`. If
infrastructure changes between the two (another engineer applies, a resource
is modified manually, drift occurs), the apply operates on different state
than what was reviewed. The reviewed plan is no longer accurate.

**Safeguard most teams skip:** Saving the plan to a file and applying from
that file (`terraform plan -out=reviewed.tfplan` + `terraform apply reviewed.tfplan`).
Most teams run `terraform apply` directly, which generates a fresh plan at
apply time. This means the apply can differ from what was reviewed — defeating
the entire purpose of the review step.

---

## Tests to Run — Complete Reference

### Local (no AWS credentials needed)

```bash
cd day_21/webserver-cluster

# 1. Format check
terraform fmt -check -recursive

# 2. Syntax and type validation
terraform init -backend=false
terraform validate

# 3. Unit tests — 14 assertions, all plan-only
terraform test

# Expected output:
# run "validate_asg_name_prefix"... pass
# run "validate_instance_type"... pass
# run "validate_health_check_type"... pass
# run "validate_alb_sg_port"... pass
# run "validate_environment_tag"... pass
# run "validate_high_cpu_alarm_name"... pass
# run "validate_high_cpu_alarm_threshold"... pass
# run "validate_high_cpu_alarm_operator"... pass
# run "validate_low_cpu_alarm_name"... pass
# run "validate_low_cpu_alarm_threshold"... pass
# run "validate_low_cpu_alarm_operator"... pass
# run "validate_unhealthy_hosts_alarm"... pass
# run "validate_sns_topic_name"... pass
# run "reject_invalid_environment"... pass
# run "reject_invalid_instance_type"... pass
# 15 tests, 0 failures
```

### With AWS credentials (post-apply verification)

```bash
# Confirm new alarm exists
aws cloudwatch describe-alarms \
  --alarm-name-prefix "belinda-day21" \
  --query 'MetricAlarms[*].{Name:AlarmName,State:StateValue,Threshold:Threshold}' \
  --output table

# Confirm state is clean after apply
terraform plan -detailed-exitcode
# Exit code 0 = clean, 1 = error, 2 = changes pending

# Confirm ASG output
terraform output asg_name

# Confirm all alarm outputs
terraform output cloudwatch_alarms

# Confirm S3 state versioning
aws s3api get-bucket-versioning \
  --bucket belinda-terraform-state-30daychallenge \
  --query 'Status'
```

---

## Challenges and Fixes

**Plan file handling:** The plan file (`day21.tfplan`) is a binary — do not
commit it to Git. Add `*.tfplan` to `.gitignore`. The plan file is only valid
for the state version it was generated against; regenerate it if state changes
between plan and apply.

**Sentinel configuration:** Sentinel requires a Terraform Cloud Plus or
Business tier. On free/trial tiers, use `enforcement_level = "advisory"` to
log warnings without blocking applies while testing the policy.

**Approval gates:** Terraform Cloud's manual apply mode (Settings → General →
Apply Method → Manual apply) is the simplest approval gate. For destructive
changes, add a required reviewer to the workspace and document the second
approval in the PR comments.

**`terraform init -backend=false`:** Required for local unit tests when the
backend is Terraform Cloud, because the test runner cannot authenticate to TFC
in CI without credentials. The `-backend=false` flag skips backend
initialisation so `terraform test` can run plan-only assertions without
connecting to TFC.
