# sentinel.hcl
# Terraform Cloud reads this file to discover and configure Sentinel policies.
# Upload this directory to a VCS-backed policy set in your TFC organisation.
#
# Enforcement levels:
#   advisory   — logs a warning, never blocks apply
#   soft-mandatory — blocks apply but an operator can override
#   hard-mandatory — blocks apply with NO override possible

policy "require-instance-type" {
  source            = "./require-instance-type.sentinel"
  enforcement_level = "soft-mandatory"
}
