# The name is the contract with bootstrap/*: they look the pool up by it. Change it in both places or nowhere.
variable "name" {
  type        = string
  default     = "elevated-engines"
  description = "Worker pool name. Every bootstrap root's elevated_worker_pool_name must match."

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,62}$", var.name))
    error_message = "name must be lowercase alphanumeric/hyphen, 2-63 chars."
  }
}

# Worker pools obey Space entity inheritance: a stack can only use a pool in its own Space or in an
# ancestor Space it inherits from. Root reaches every Space that inherits; a Space with
# inherit_entities = false needs its own pool.
variable "space_id" {
  type        = string
  default     = "root"
  description = "Space the pool lives in. Must be reachable from every elevated stack's Space."

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$", var.space_id))
    error_message = "space_id must be a Space ID (slug), e.g. \"root\"."
  }
}
