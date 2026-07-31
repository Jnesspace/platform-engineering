# Role and binding IDs are the privileged objects in this root; keep them out of CI logs.
output "role_ids" {
  value       = { requester = spacelift_role.requester.id, approver = spacelift_role.approver.id, reader = spacelift_role.reader.id }
  description = "The custom role ULIDs."
  sensitive   = true
}

output "bindings" {
  description = "Who holds which half of the split, and where — the separation-of-duties evidence."
  value = {
    requester = sort(keys(spacelift_role_attachment.requester))
    approver  = sort(keys(spacelift_role_attachment.approver))
    reader    = sort(keys(spacelift_role_attachment.reader))
  }
}
