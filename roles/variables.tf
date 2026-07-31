# Subjects are IdP group NAMES, resolved to mappings at plan time — no account-specific ULIDs here.
# For a user or API-key subject, the resource is the same with user_id / api_key_id instead.

# Required, and required to be non-empty: an unbound requester/approver split enforces nothing, which
# is how docs/hardening-backlog.md item 2 stayed open while the roles already existed.
variable "requester_groups" {
  type        = set(string)
  description = "IdP group names that may TRIGGER runs (and not confirm them)."

  validation {
    condition     = length(var.requester_groups) > 0
    error_message = "requester_groups must name at least one IdP group; the split only exists once it is bound."
  }
}

variable "approver_groups" {
  type        = set(string)
  description = "IdP group names that may CONFIRM runs (and not trigger them). Must be disjoint from requester_groups."

  validation {
    condition     = length(var.approver_groups) > 0
    error_message = "approver_groups must name at least one IdP group; without an approver every gate stalls or gets self-approved."
  }
}

variable "reader_groups" {
  type        = set(string)
  default     = []
  description = "IdP group names that get read-only visibility."
}

# Attachments are Space-scoped: there is no stack-scoped human binding in Spacelift RBAC. Scope a
# team to one entry point by giving that Space exactly one stack (as bootstrap/nonadmin-launcher does).
variable "governed_spaces" {
  type        = set(string)
  description = "Spaces to bind these roles in."

  validation {
    condition     = length(var.governed_spaces) > 0
    error_message = "governed_spaces must list at least one Space."
  }

  validation {
    condition     = alltrue([for s in var.governed_spaces : can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$", s))])
    error_message = "Each governed_spaces entry must be a Space ID (slug), e.g. \"platform-01H8...\"."
  }
}
