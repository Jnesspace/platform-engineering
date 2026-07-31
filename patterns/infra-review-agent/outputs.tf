output "context_id" {
  value       = spacelift_context.this.id
  description = "ID of the review-agent context (for explicit spacelift_context_attachment, if autoattach labels are not used)."
}

output "opt_in_labels" {
  value       = [for l in var.labels : trimprefix(l, "autoattach:") if startswith(l, "autoattach:")]
  description = "Stack labels that opt a stack into plan review (e.g. add `infra-review` to spacelift_stack.labels)."
}

output "agent_path" {
  value       = "/mnt/workspace/${var.agent_relative_path}"
  description = "Absolute path of the mounted agent script inside workers."
}

output "posture" {
  value       = "run_types=${join(",", var.run_types)} fail_on=${var.fail_on} api_key=${var.anthropic_api_key != "" ? "set" : "UNSET (agent skips)"}"
  description = "One-line summary of the deployed posture."
}
