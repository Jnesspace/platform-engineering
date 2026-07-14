# Reusable custom roles: the requester/approver split from docs/hardening-backlog.md item 2.

# Can trigger runs but not confirm them — the confirm gate belongs to someone else.
resource "spacelift_role" "requester" {
  name        = "requester"
  description = "Read + trigger runs. Cannot confirm — pairs with `approver` to break self-approval."
  actions     = ["SPACE_READ", "RUN_TRIGGER"]
}

# Can confirm runs but not trigger them — the other half of the split.
resource "spacelift_role" "approver" {
  name        = "approver"
  description = "Read + confirm runs. Cannot trigger — pairs with `requester` to break self-approval."
  actions     = ["SPACE_READ", "RUN_CONFIRM"]
}

# Read-only visibility, no run actions.
resource "spacelift_role" "reader" {
  name        = "reader"
  description = "Read-only Space visibility."
  actions     = ["SPACE_READ"]
}

# The current combined role (trigger + confirm in one) — self-approvable; kept for comparison.
resource "spacelift_role" "consumer" {
  name        = "consumer"
  description = "Combined read + trigger + confirm. Self-approvable — prefer the requester/approver split."
  actions     = ["SPACE_READ", "RUN_TRIGGER", "RUN_CONFIRM"]
}
