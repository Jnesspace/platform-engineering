# One context delivers the whole agent: the script (mounted file), its
# configuration (environment variables), and the wiring (after_plan hooks).
# Stacks opt in with a single label; nothing is edited per stack.

locals {
  # The plan file lives in the project root (the hook's cwd). The printf fallback
  # keeps a failed `terraform show` (e.g. a run with no plan) from failing the hook.
  hook_dump_plan = "terraform show -json spacelift.plan > /tmp/infra-review.plan.json 2>/dev/null || printf '{}' > /tmp/infra-review.plan.json"

  # Node-guard: a runner image without Node >= 18 skips the review instead of
  # failing the run. When node exists, the agent's own exit code stands, so
  # fail_on=findings/error can still block the run.
  hook_run_agent = "if command -v node >/dev/null 2>&1; then node /mnt/workspace/${var.agent_relative_path} /tmp/infra-review.plan.json; else echo 'infra-review: runner image has no node >= 18 - skipping review'; fi"
}

resource "spacelift_context" "this" {
  name        = var.name
  description = var.description
  space_id    = var.space_id
  labels      = var.labels

  after_plan = [local.hook_dump_plan, local.hook_run_agent]
}

# The agent itself. Source of truth is agents/infra-review/agent.mjs in this
# repo; mounted under /mnt/workspace so it works for stacks on ANY repository,
# not just this one. Not write-only: it is code, not a secret, and operators
# should be able to verify the checksum.
resource "spacelift_mounted_file" "agent" {
  context_id    = spacelift_context.this.id
  relative_path = var.agent_relative_path
  content       = filebase64("${path.module}/../../agents/infra-review/agent.mjs")
  write_only    = false
  description   = "Infra review agent entrypoint. Edit agents/infra-review/agent.mjs and re-apply this pattern."
}

resource "spacelift_environment_variable" "api_key" {
  count = var.anthropic_api_key != "" ? 1 : 0

  context_id = spacelift_context.this.id
  name       = "ANTHROPIC_API_KEY"
  value      = var.anthropic_api_key
  write_only = true
}

resource "spacelift_environment_variable" "model" {
  context_id = spacelift_context.this.id
  name       = "INFRA_REVIEW_MODEL"
  value      = var.model
  write_only = false
}

resource "spacelift_environment_variable" "run_types" {
  context_id = spacelift_context.this.id
  name       = "INFRA_REVIEW_RUN_TYPES"
  value      = join(",", var.run_types)
  write_only = false
}

resource "spacelift_environment_variable" "fail_on" {
  context_id = spacelift_context.this.id
  name       = "INFRA_REVIEW_FAIL_ON"
  value      = var.fail_on
  write_only = false
}

resource "spacelift_environment_variable" "max_plan_bytes" {
  context_id = spacelift_context.this.id
  name       = "INFRA_REVIEW_MAX_PLAN_BYTES"
  value      = tostring(var.max_plan_bytes)
  write_only = false
}

resource "spacelift_environment_variable" "api_base_url" {
  context_id = spacelift_context.this.id
  name       = "ANTHROPIC_BASE_URL"
  value      = var.api_base_url
  write_only = false
}

resource "spacelift_environment_variable" "spec" {
  count = var.spec != "" ? 1 : 0

  context_id = spacelift_context.this.id
  name       = "INFRA_REVIEW_SPEC"
  value      = var.spec
  write_only = false
}

resource "spacelift_environment_variable" "spec_file" {
  count = var.spec_file != "" ? 1 : 0

  context_id = spacelift_context.this.id
  name       = "INFRA_REVIEW_SPEC_FILE"
  value      = var.spec_file
  write_only = false
}
