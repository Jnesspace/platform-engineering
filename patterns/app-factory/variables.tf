variable "shopping_list_file" {
  description = "Path to the app's shopping list (platform.yaml). Relative paths resolve against this directory."
  type        = string
  default     = "../../examples/jimmy-app/platform.yaml"
}

variable "shopping_list_yaml" {
  description = "Inline shopping list (YAML). When set, used instead of shopping_list_file — the Blueprint/form path."
  type        = string
  default     = ""
}

variable "app_name" {
  description = "Override for the app name. Empty means: use the shopping list's `name:`."
  type        = string
  default     = ""
}

variable "region" {
  description = "AWS region for the vended resources."
  type        = string
  default     = "us-east-1"
}
