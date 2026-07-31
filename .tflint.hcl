# tflint for a multi-cloud module library.
#
# Rule selection principle: lint for what breaks a *consumer* of a module —
# untyped or undeclared variables, unpinned module sources, missing provider
# constraints — not for style. `terraform fmt` already owns style, and a linter
# that argues with fmt is a linter people switch off.

tflint {
  required_version = ">= 0.55"
}

config {
  # Every module directory is validated in its own right (the CI matrix is built
  # from where .tf files live, not from what the roots call), so descending into
  # called modules would report each finding once per caller instead of once.
  call_module_type = "none"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# Cloud rulesets catch the class of error `terraform validate` cannot: values
# that are syntactically fine but rejected by the API (bad instance types,
# invalid IAM policy documents, name-length limits). Deep checking — the mode
# that calls the cloud API — is deliberately left off: no credentials exist in
# this repo's CI and none may.
plugin "aws" {
  enabled = true
  version = "0.48.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

plugin "azurerm" {
  enabled = true
  version = "0.32.0"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}

plugin "google" {
  enabled = true
  version = "0.39.0"
  source  = "github.com/terraform-linters/tflint-ruleset-google"
}

# A reusable module must not decide its consumers' deletion policy. This repo
# ships ephemeral environments with TTL teardown (schedules/ephemeral-ttl), so a
# rule demanding lifecycle { prevent_destroy = true } on every stateful resource
# in a module would make the modules unusable for half their intended callers.
# prevent_destroy belongs in the root that owns the data, not in the wrapper.
rule "azurerm_resources_missing_prevent_destroy" {
  enabled = false
}

# `examples/basic` directories intentionally inherit provider requirements from
# the module they call rather than restating them, so the two "declare your
# requirements" rules would fail on arrival for a third of the tree. They are
# the right rules for the roots that Spacelift actually executes — promote them
# once modules/ owns a versions.tf everywhere (see the report / backlog).
rule "terraform_required_providers" {
  enabled = false
}

rule "terraform_required_version" {
  enabled = false
}
