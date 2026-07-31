variable "app_name" {
  description = "App name; names the workload objects and the default namespace."
  type        = string

  validation {
    # Also half of app-factory's IRSA `sub`, so it must be a DNS-1123 label.
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.app_name))
    error_message = "app_name must be a DNS-1123 label: lowercase alphanumeric or hyphen, starting and ending alphanumeric, <= 63 chars."
  }
}

variable "image" {
  description = "Container image to run (the app repo's Dockerfile, built and pushed)."
  type        = string

  validation {
    condition     = trimspace(var.image) != ""
    error_message = "image must be set."
  }
}

variable "app_role_arn" {
  description = "app-factory's `app_role_arn` output — the role the pod assumes via IRSA."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", var.app_role_arn))
    error_message = "app_role_arn must be an IAM role ARN (arn:aws:iam::<account>:role/<name>)."
  }
}

variable "bucket" {
  description = "Bucket name, from app-factory's `resource_access[\"object_storage/<name>\"].bucket`."
  type        = string
}

variable "secret_arn" {
  description = "Secret ARN, from app-factory's `resource_access[\"secrets/<name>\"].secret_ref`."
  type        = string
}

variable "region" {
  description = "AWS region the vended resources live in; injected as AWS_REGION."
  type        = string
  default     = "us-east-1"
}

variable "namespace" {
  description = "Namespace for the app. Empty means: use `app_name`. Must match app-factory's `app_role_trust.namespace` or the IRSA `sub` won't match."
  type        = string
  default     = ""

  validation {
    condition     = var.namespace == "" || can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a DNS-1123 label."
  }
}

variable "replicas" {
  description = "Deployment replica count."
  type        = number
  default     = 2

  validation {
    condition     = var.replicas >= 1 && var.replicas <= 50
    error_message = "replicas must be between 1 and 50."
  }
}

variable "container_port" {
  description = "Port the container listens on; the ClusterIP Service exposes it."
  type        = number
  default     = 8080

  validation {
    # Ports below 1024 need a capability the hardened container has dropped.
    condition     = var.container_port >= 1024 && var.container_port <= 65535
    error_message = "container_port must be 1024-65535: the container drops ALL capabilities, so it cannot bind a privileged port."
  }
}

# --- IRSA credential path (see main.tf) ---

variable "project_irsa_token" {
  description = "Project the sts.amazonaws.com service-account token into the pod explicitly, which lets the Kubernetes API token stay unmounted. Set false to rely on the EKS pod-identity webhook instead — that path needs the automounted token, so the pod then also carries a Kubernetes API credential."
  type        = bool
  default     = true
}

variable "irsa_token_expiration_seconds" {
  description = "Lifetime of the projected AWS web-identity token; the kubelet rotates it. Matches the pod-identity webhook's default."
  type        = number
  default     = 86400

  validation {
    condition     = var.irsa_token_expiration_seconds >= 600 && var.irsa_token_expiration_seconds <= 86400
    error_message = "irsa_token_expiration_seconds must be 600-86400 (the Kubernetes TokenRequest bounds)."
  }
}

# --- Pod hardening. Defaults are the secure values; loosen deliberately. ---

variable "pod_security_standard" {
  description = "Pod Security Standard enforced on the namespace."
  type        = string
  default     = "restricted"

  validation {
    condition     = contains(["restricted", "baseline", "privileged"], var.pod_security_standard)
    error_message = "pod_security_standard must be restricted, baseline or privileged."
  }
}

variable "run_as_user" {
  description = "UID the container runs as. null uses the image's own USER, which must still be non-root."
  type        = number
  default     = 10001

  validation {
    condition     = var.run_as_user == null || var.run_as_user > 0
    error_message = "run_as_user must be greater than 0 (running as root is refused) or null to use the image's USER."
  }
}

variable "run_as_group" {
  description = "GID the container runs as. null uses the image's own group."
  type        = number
  default     = 10001

  validation {
    condition     = var.run_as_group == null || var.run_as_group > 0
    error_message = "run_as_group must be greater than 0 or null."
  }
}

variable "fs_group" {
  description = "Supplemental group applied to mounted volumes so a non-root container can write its scratch space."
  type        = number
  default     = 10001

  validation {
    condition     = var.fs_group == null || var.fs_group > 0
    error_message = "fs_group must be greater than 0 or null."
  }
}

variable "cpu_request" {
  description = "CPU request."
  type        = string
  default     = "100m"
}

variable "cpu_limit" {
  description = "CPU limit."
  type        = string
  default     = "500m"
}

variable "memory_request" {
  description = "Memory request."
  type        = string
  default     = "128Mi"
}

variable "memory_limit" {
  description = "Memory limit — also the OOM boundary, so one app cannot starve the node."
  type        = string
  default     = "512Mi"
}

variable "tmp_volume_size" {
  description = "Size limit of the /tmp emptyDir the read-only root filesystem needs."
  type        = string
  default     = "64Mi"
}

variable "liveness_path" {
  description = "HTTP path for the liveness probe. Empty falls back to a TCP connect on container_port."
  type        = string
  default     = "/healthz"
}

variable "readiness_path" {
  description = "HTTP path for the readiness probe. Empty falls back to a TCP connect on container_port."
  type        = string
  default     = "/readyz"
}

variable "liveness_initial_delay_seconds" {
  description = "Grace period before the first liveness probe, so a slow starter isn't killed."
  type        = number
  default     = 15
}

# --- Network policy ---

variable "enable_network_policy" {
  description = "Create the default-deny NetworkPolicy plus the app's allow-list. Only turn this off on a cluster whose CNI cannot enforce NetworkPolicy — where the objects would give false assurance."
  type        = bool
  default     = true
}

variable "dns_namespace" {
  description = "Namespace running cluster DNS, selected by the `kubernetes.io/metadata.name` label for the egress DNS rule."
  type        = string
  default     = "kube-system"
}

variable "ingress_namespace_labels" {
  description = "Extra ingress sources as namespace label selectors, e.g. [{ \"kubernetes.io/metadata.name\" = \"ingress-nginx\" }]. Empty means same-namespace traffic only."
  type        = list(map(string))
  default     = []
}

variable "egress_cidr" {
  description = "CIDR the app may reach on egress_ports — the AWS API surface. Narrow it to your VPC endpoints if you have them."
  type        = string
  default     = "0.0.0.0/0"
}

variable "egress_except_cidrs" {
  description = "CIDRs carved out of egress_cidr. Defaults to the IMDS address so a compromised pod cannot pick up the node's instance role."
  type        = list(string)
  default     = ["169.254.169.254/32"]
}

variable "egress_ports" {
  description = "TCP ports allowed to egress_cidr. 443 covers STS, S3 and Secrets Manager; add ports only for what the app actually calls."
  type        = list(string)
  default     = ["443"]
}
