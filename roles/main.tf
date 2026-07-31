# Reusable custom roles AND their bindings: docs/hardening-backlog.md item 2. Defining the split is
# half the control; the other half is that no subject is ever granted both halves.

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

# The combined `consumer` role (SPACE_READ + RUN_TRIGGER + RUN_CONFIRM) is GONE, not deprecated:
# it made every confirm gate self-approvable, and a role that exists is a role someone attaches.

# Resolve IdP groups by their SSO name so no ULID is hardcoded.
data "spacelift_idp_group_mapping" "requester" {
  for_each = var.requester_groups
  name     = each.key
}

data "spacelift_idp_group_mapping" "approver" {
  for_each = var.approver_groups
  name     = each.key
}

data "spacelift_idp_group_mapping" "reader" {
  for_each = var.reader_groups
  name     = each.key
}

locals {
  # An attachment binds one role to one subject in one Space, so every (group, Space) pair is a resource.
  requester_bindings = { for p in setproduct(tolist(var.requester_groups), tolist(var.governed_spaces)) : "${p[0]}@${p[1]}" => { group = p[0], space = p[1] } }
  approver_bindings  = { for p in setproduct(tolist(var.approver_groups), tolist(var.governed_spaces)) : "${p[0]}@${p[1]}" => { group = p[0], space = p[1] } }
  reader_bindings    = { for p in setproduct(tolist(var.reader_groups), tolist(var.governed_spaces)) : "${p[0]}@${p[1]}" => { group = p[0], space = p[1] } }

  both_halves = setintersection(var.requester_groups, var.approver_groups)
}

# THE control. Terraform 1.5 cannot compare two variables inside a validation block, so the
# separation-of-duties check lives here: plan-time, no credentials needed.
resource "terraform_data" "separation_of_duties" {
  input = {
    requester = sort(tolist(var.requester_groups))
    approver  = sort(tolist(var.approver_groups))
  }

  lifecycle {
    precondition {
      condition     = length(local.both_halves) == 0
      error_message = "Group(s) ${join(", ", local.both_halves)} appear in both requester_groups and approver_groups. A subject holding RUN_TRIGGER and RUN_CONFIRM can approve its own run — exactly what the split exists to prevent."
    }
  }
}

resource "spacelift_role_attachment" "requester" {
  for_each = local.requester_bindings

  role_id              = spacelift_role.requester.id
  space_id             = each.value.space
  idp_group_mapping_id = data.spacelift_idp_group_mapping.requester[each.value.group].id
}

resource "spacelift_role_attachment" "approver" {
  for_each = local.approver_bindings

  role_id              = spacelift_role.approver.id
  space_id             = each.value.space
  idp_group_mapping_id = data.spacelift_idp_group_mapping.approver[each.value.group].id
}

resource "spacelift_role_attachment" "reader" {
  for_each = local.reader_bindings

  role_id              = spacelift_role.reader.id
  space_id             = each.value.space
  idp_group_mapping_id = data.spacelift_idp_group_mapping.reader[each.value.group].id
}
