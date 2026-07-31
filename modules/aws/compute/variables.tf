variable "name" {
  description = "Logical name; used for the instance Name tag and derived resource names."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9._-]{0,60}[a-zA-Z0-9]$", var.name))
    error_message = "name must be 2-62 chars, start and end alphanumeric, and contain only letters, digits, dots, hyphens or underscores (the security group name is derived from it)."
  }
}

variable "tags" {
  description = "Tags applied to every resource this module creates."
  type        = map(string)
  default     = {}
}

variable "instance_type" {
  description = "EC2 instance type. Small tier by default."
  type        = string
  default     = "t3.micro"

  validation {
    condition     = can(regex("^[a-z0-9-]+\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must look like <family>.<size>, e.g. t3.micro."
  }
}

variable "vpc_id" {
  description = "VPC for the security group. Null discovers the account's default VPC."
  type        = string
  default     = null

  validation {
    condition     = var.vpc_id == null || can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be null or a vpc-... id."
  }
}

variable "subnet_id" {
  description = "Subnet to launch into. Null picks the first default subnet of the resolved VPC; production should pass a private subnet."
  type        = string
  default     = null

  validation {
    condition     = var.subnet_id == null || can(regex("^subnet-[0-9a-f]+$", var.subnet_id))
    error_message = "subnet_id must be null or a subnet-... id."
  }
}

variable "assign_public_ip" {
  description = "Attach a public IP. Off by default — default subnets would otherwise hand one out silently."
  type        = bool
  default     = false
}

variable "ingress_rules" {
  description = "Inbound rules for the instance security group. Empty means no inbound at all. Internet-wide CIDRs are rejected at plan time; front the instance with a load balancer instead."
  type = list(object({
    description = optional(string, "")
    from_port   = number
    to_port     = number
    protocol    = optional(string, "tcp")
    cidr_blocks = list(string)
  }))
  default = []

  validation {
    condition = alltrue([
      for r in var.ingress_rules : !contains(r.cidr_blocks, "0.0.0.0/0") && !contains(r.cidr_blocks, "::/0")
    ])
    error_message = "ingress_rules must not contain 0.0.0.0/0 or ::/0."
  }

  validation {
    condition = alltrue([
      for r in var.ingress_rules : r.from_port >= 0 && r.to_port >= r.from_port && r.to_port <= 65535
    ])
    error_message = "ingress_rules ports must satisfy 0 <= from_port <= to_port <= 65535."
  }
}

variable "egress_cidr_blocks" {
  description = "Destinations the instance may reach. Wide open by default because package mirrors and AWS APIs are; narrow it where you have an egress proxy."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "kms_key_arn" {
  description = "Customer-managed KMS key ARN for the root EBS volume. Empty falls back to the AWS-managed aws/ebs key — the volume is encrypted either way. EC2 handles volume decryption itself, so this adds nothing to iam_policy_json."
  type        = string
  default     = ""

  validation {
    condition     = var.kms_key_arn == "" || can(regex("^arn:aws[a-z-]*:kms:", var.kms_key_arn))
    error_message = "kms_key_arn must be empty or a KMS key ARN (arn:aws:kms:...)."
  }
}

variable "root_volume_size_gb" {
  description = "Root volume size in GiB."
  type        = number
  default     = 20

  validation {
    condition     = var.root_volume_size_gb >= 8 && var.root_volume_size_gb <= 16384
    error_message = "root_volume_size_gb must be between 8 and 16384."
  }
}

variable "imds_hop_limit" {
  description = "IMDS PUT response hop limit. 1 keeps credentials unreachable from a container on the host; raise to 2 only if you run containers that need IMDS."
  type        = number
  default     = 1

  validation {
    condition     = var.imds_hop_limit >= 1 && var.imds_hop_limit <= 64
    error_message = "imds_hop_limit must be between 1 and 64."
  }
}

variable "iam_instance_profile" {
  description = "Existing instance profile to attach, e.g. the app role vended by app-factory. Null attaches none, so the instance has no AWS credentials at all."
  type        = string
  default     = null
}

variable "detailed_monitoring" {
  description = "One-minute CloudWatch metrics instead of five-minute. Off by default because it is billed per instance."
  type        = bool
  default     = false
}

variable "disable_api_termination" {
  description = "EC2 termination protection. Off by default: a stateless VM is meant to be replaceable, and on makes terraform destroy fail outright."
  type        = bool
  default     = false
}
