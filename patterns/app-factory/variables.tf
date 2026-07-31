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

  validation {
    # Prefixes every resource name and must start with a letter (RDS identifiers do); the role is <app_name>-app, capped at 64.
    condition     = var.app_name == "" || can(regex("^[a-z][a-z0-9]*(-[a-z0-9]+)*$", var.app_name))
    error_message = "app_name must be lowercase, start with a letter, and use single hyphens as separators."
  }

  validation {
    condition     = length(var.app_name) <= 40
    error_message = "app_name must be <= 40 chars: it prefixes bucket names (63-char cap) and the role name <app_name>-app (64-char cap)."
  }
}

variable "region" {
  description = "AWS region for the vended resources."
  type        = string
  default     = "us-east-1"
}

# --- Required tags (policies/plan/enforce-required-tags.rego denies a run without Environment/Owner/Project) ---

variable "environment" {
  description = "Environment lane this stack vends into (dev / stage / prod). Becomes the Environment tag on every resource. Operator-only: bootstrap/environments already labels each app-factory stack env:<environment>, and policies/plan/protect-env-labels.rego treats env:* as a privilege claim — a team naming its own would be claiming that privilege. Empty fails the plan with a message instead of tagging something wrong."
  type        = string
  default     = ""

  validation {
    condition     = var.environment == "" || (can(regex("^[a-z0-9]([a-z0-9]|-[a-z0-9])*$", var.environment)) && length(var.environment) <= 20)
    error_message = "environment must be lowercase alphanumerics separated by single hyphens, <= 20 chars (e.g. dev, stage, prod)."
  }
}

variable "owner" {
  description = "Owning team; becomes the Owner tag. Wins over the shopping list's `owner:` — a Blueprint form or a per-env stack knows the team authoritatively, while a team's own repo is where it declares one otherwise. Empty on both sides fails the plan."
  type        = string
  default     = ""

  validation {
    condition     = var.owner == "" || (can(regex("^[a-z0-9]([a-z0-9]|-[a-z0-9])*$", var.owner)) && length(var.owner) <= 40)
    error_message = "owner must be lowercase alphanumerics separated by single hyphens, <= 40 chars — the same charset as the stack's team: label."
  }
}

# --- App role trust (see iam.tf) ---

variable "trust_mode" {
  description = "How the app role is assumed: \"irsa\" (EKS ServiceAccount, requires eks_oidc_provider_arn) or \"ec2\" (the non-Kubernetes case)."
  type        = string
  default     = "irsa"

  validation {
    condition     = contains(["irsa", "ec2"], var.trust_mode)
    error_message = "trust_mode must be \"irsa\" or \"ec2\"."
  }
}

variable "eks_oidc_provider_arn" {
  description = "IAM OIDC provider ARN of the EKS cluster app-deploy targets, e.g. arn:aws:iam::111122223333:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE. Required when trust_mode = \"irsa\"."
  type        = string
  default     = ""

  validation {
    condition     = var.eks_oidc_provider_arn == "" || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:oidc-provider/oidc\\.eks\\.[a-z0-9-]+\\.amazonaws\\.com/id/[A-Za-z0-9]+$", var.eks_oidc_provider_arn))
    error_message = "eks_oidc_provider_arn must be an EKS cluster OIDC provider ARN: arn:aws:iam::<account>:oidc-provider/oidc.eks.<region>.amazonaws.com/id/<hash>."
  }
}

variable "k8s_namespace" {
  description = "Namespace the pod runs in, used in the IRSA `sub`. Empty means: use the app name — which is what app-deploy defaults to."
  type        = string
  default     = ""
}

variable "k8s_service_account" {
  description = "ServiceAccount name used in the IRSA `sub`. Empty means: use the app name — app-deploy names the ServiceAccount after the app."
  type        = string
  default     = ""
}

variable "app_role_permissions_boundary_arn" {
  description = "Optional permissions boundary for the app role — a runtime hard cap on top of the aggregated grants (e.g. iam-factory's boundary_policy_arn). A boundary is an INTERSECTION: if a CMK is in play it must also allow kms:Decrypt/GenerateDataKey/DescribeKey, or the app fails at runtime with an error naming the key. See the cmk_needs_boundary_kms check in main.tf."
  type        = string
  default     = ""

  validation {
    # A malformed boundary ARN is rejected by IAM at apply with a message about the role, not the boundary.
    condition     = var.app_role_permissions_boundary_arn == "" || can(regex("^arn:aws[a-z-]*:iam::([0-9]{12}|aws):policy/", var.app_role_permissions_boundary_arn))
    error_message = "app_role_permissions_boundary_arn must be empty or an IAM policy ARN (arn:aws:iam::<account>:policy/<name>, or arn:aws:iam::aws:policy/<name> for an AWS-managed one)."
  }
}

# --- Shopping-list guardrails (the list is team-supplied, i.e. untrusted input) ---

variable "max_resources" {
  description = "Cap on total entries in one shopping list. An unbounded list is a cost and blast-radius problem, and the cap-new-resources plan policy denies plans over 25 resources anyway."
  type        = number
  default     = 10

  validation {
    condition     = var.max_resources >= 1 && var.max_resources <= 25
    error_message = "max_resources must be between 1 and 25."
  }
}

variable "reserved_names" {
  description = "Resource names a shopping list may not use: AWS-reserved prefixes and names that collide with platform-managed objects."
  type        = list(string)
  default     = ["aws", "amazon", "default", "terraform", "tfstate", "kube-system"]
}

# --- Platform posture: operator-only, set on the STACK ---
#
# The split these implement: a shopping list may only move a control in the
# strengthening or neutral direction, so nothing a team writes in its own repo
# can weaken a default. Anything that makes data easier to destroy, or that
# redirects an audit trail, is a stack variable — the team has no write access
# to the stack, so setting it is an operator act with an audit trail.

variable "allowed_kms_key_arns" {
  description = "CMKs a shopping list may name in a resource's `kms_key_arn`. Empty means the platform has published none, so any `kms_key_arn:` in the list is rejected: a team picks among the platform's keys, it does not bring its own. An arbitrary key would put the app's data under something the platform cannot read and the team can revoke."
  type        = list(string)
  default     = []

  validation {
    # Repeated in main.tf's kms_arn_pattern: a variable validation cannot reference a local.
    condition     = alltrue([for a in var.allowed_kms_key_arns : can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/(mrk-[0-9a-f]{32}|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$", a))])
    error_message = "allowed_kms_key_arns entries must be KMS *key* ARNs (arn:aws:kms:<region>:<account>:key/<uuid|mrk-...>). Alias ARNs are rejected: an identity policy naming an alias grants nothing on the key behind it, so the app 403s at runtime."
  }
}

variable "default_kms_key_arn" {
  description = "CMK applied to every vended resource that does not name its own. Empty falls back to the AWS-managed keys (aws/s3, aws/rds, aws/secretsmanager, aws/ebs) — encrypted either way. Operator-set, so it needs no allow-list entry: it IS the allow."
  type        = string
  default     = ""

  validation {
    condition     = var.default_kms_key_arn == "" || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/(mrk-[0-9a-f]{32}|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$", var.default_kms_key_arn))
    error_message = "default_kms_key_arn must be empty or a KMS key ARN (arn:aws:kms:<region>:<account>:key/<uuid|mrk-...>), not an alias ARN."
  }
}

variable "access_log_bucket" {
  description = "Bucket receiving S3 server access logs for every vended bucket. Operator-only because it is an audit trail's destination: a team must be able to neither switch it off nor point it at a bucket the platform does not own. Empty disables access logging; the target must already permit logging.s3.amazonaws.com to write."
  type        = string
  default     = ""

  validation {
    condition     = var.access_log_bucket == "" || can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.access_log_bucket))
    error_message = "access_log_bucket must be empty or a valid S3 bucket name (3-63 chars, lowercase)."
  }
}

variable "demo_teardown" {
  description = "THE posture-weakening escape hatch, and deliberately the only one: buckets get force_destroy, the database gives up deletion protection and its final snapshot, and credential secrets get a 0-day recovery window so `terraform destroy` succeeds and the names free immediately. Ephemeral/demo environments only. A stack variable, never a shopping-list field — a team able to set this from its own repo would have a one-line route to making its own data trivially destroyable, which is the class of thing this repo's guardrails exist to prevent."
  type        = bool
  default     = false
}
