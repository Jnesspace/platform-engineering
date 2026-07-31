variable "name" {
  type        = string
  default     = "infra-review-agent"
  description = "Name of the Spacelift context that carries the review agent."
}

variable "description" {
  type        = string
  default     = "AI plan review agent (PoC). Mounts the agent, injects its config, and runs it after every plan on attached stacks."
  description = "Human-readable description shown on the context."
}

variable "space_id" {
  type        = string
  default     = "root"
  description = "Space the context lives in. Attachments only flow to stacks that can see this Space."
}

variable "labels" {
  type        = set(string)
  default     = ["autoattach:infra-review"]
  description = "Context labels. At least one must be an autoattach: label — stacks opt in by carrying the matching bare label (e.g. `infra-review`)."

  validation {
    condition     = length([for l in var.labels : l if startswith(l, "autoattach:")]) > 0
    error_message = "labels must include at least one autoattach:<label> entry, or the context never reaches a stack."
  }
}

variable "anthropic_api_key" {
  type        = string
  sensitive   = true
  default     = ""
  description = "Anthropic API key, set as a write-only ANTHROPIC_API_KEY on the context. Leave empty to deploy the context inert: the agent logs a skip on every run until a key is set."
}

variable "model" {
  type        = string
  default     = "claude-sonnet-4-5"
  description = "Anthropic model ID the agent reviews plans with."
}

variable "run_types" {
  type        = set(string)
  default     = ["PROPOSED"]
  description = "Spacelift run types the agent reviews (PROPOSED = PR runs only), or ALL."

  validation {
    condition     = length(setsubtract(var.run_types, ["PROPOSED", "TRACKED", "TASK", "TESTING", "DESTROY", "PARSE", "ALL"])) == 0
    error_message = "run_types must be drawn from PROPOSED, TRACKED, TASK, TESTING, DESTROY, PARSE, or ALL."
  }
}

variable "fail_on" {
  type        = string
  default     = "never"
  description = "When the agent fails the run: never (advisory), findings (fail verdict or high/critical findings), or error (the review itself errored)."

  validation {
    condition     = contains(["never", "findings", "error"], var.fail_on)
    error_message = "fail_on must be one of: never, findings, error."
  }
}

variable "spec" {
  type        = string
  default     = ""
  description = "Inline deployment spec the plan is verified against (e.g. tagging, network, or sizing requirements). Empty = general review only."
}

variable "spec_file" {
  type        = string
  default     = ""
  description = "Path to a deployment spec file, read inside the worker. The agent enforces containment: relative paths only, realpath-resolved under each stack's project root. Empty = disabled."
}

variable "max_plan_bytes" {
  type        = number
  default     = 200000
  description = "Byte budget for the raw plan JSON sent to the model; larger plans are truncated."

  validation {
    condition     = var.max_plan_bytes > 0
    error_message = "max_plan_bytes must be positive."
  }
}

variable "api_base_url" {
  type        = string
  default     = "https://api.anthropic.com"
  description = "Anthropic API base URL. Override for a proxy or self-hosted gateway."

  validation {
    condition     = can(regex("^https?://", var.api_base_url))
    error_message = "api_base_url must be an http(s) URL."
  }
}

variable "agent_relative_path" {
  type        = string
  default     = "infra-review/agent.mjs"
  description = "Where the agent script is mounted under /mnt/workspace. Must stay in sync with the hook command."

  validation {
    condition     = !startswith(var.agent_relative_path, "/") && can(regex("\\.mjs$", var.agent_relative_path))
    error_message = "agent_relative_path must be a relative path ending in .mjs."
  }
}
