variable "name" {
  description = "Logical name; used as the RDS identifier and to derive the secret name (lowercase, hyphens)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,61}[a-z0-9]$", var.name)) && !can(regex("--", var.name))
    error_message = "name must be 2-63 chars, start with a lowercase letter, contain only lowercase letters, digits and hyphens, not end with a hyphen and not contain consecutive hyphens (RDS instance identifier rules)."
  }
}

variable "tags" {
  description = "Tags applied to every resource this module creates."
  type        = map(string)
  default     = {}
}

variable "engine_version" {
  description = "PostgreSQL major (or major.minor) version. The major part also selects the parameter-group family."
  type        = string
  default     = "16"

  validation {
    condition     = can(regex("^[0-9]{1,2}(\\.[0-9]{1,2})?$", var.engine_version))
    error_message = "engine_version must be a major (\"16\") or major.minor (\"16.3\") PostgreSQL version."
  }
}

variable "instance_class" {
  description = "RDS instance class. Small tier by default."
  type        = string
  default     = "db.t3.micro"

  validation {
    condition     = can(regex("^db\\.[a-z0-9]+\\.[a-z0-9]+$", var.instance_class))
    error_message = "instance_class must look like db.<family>.<size>, e.g. db.t3.micro."
  }
}

variable "allocated_storage_gb" {
  description = "Allocated storage in GiB."
  type        = number
  default     = 20

  validation {
    condition     = var.allocated_storage_gb >= 20 && var.allocated_storage_gb <= 65536
    error_message = "allocated_storage_gb must be between 20 and 65536 (20 GiB is the RDS PostgreSQL minimum)."
  }
}

variable "storage_type" {
  description = "EBS volume type backing the instance."
  type        = string
  default     = "gp3"

  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2"], var.storage_type)
    error_message = "storage_type must be one of gp2, gp3, io1, io2."
  }
}

variable "database_name" {
  description = "Name of the initial database created inside the instance."
  type        = string
  default     = "app"

  validation {
    condition     = can(regex("^[a-zA-Z_][a-zA-Z0-9_]{0,62}$", var.database_name))
    error_message = "database_name must start with a letter or underscore and contain only letters, digits and underscores (max 63 chars)."
  }
}

variable "master_username" {
  description = "Master username. Password is generated and stored in Secrets Manager — never an input."
  type        = string
  default     = "app_admin"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,62}$", var.master_username)) && !contains(["rdsadmin", "admin", "postgres"], lower(var.master_username))
    error_message = "master_username must start with a letter, contain only letters, digits and underscores (max 63 chars), and must not be a reserved name (rdsadmin, admin, postgres)."
  }
}

variable "rotation_days" {
  description = "When > 0, regenerate the master password on the first apply after every N days. 0 disables rotation."
  type        = number
  default     = 0

  validation {
    condition     = var.rotation_days >= 0 && var.rotation_days <= 365
    error_message = "rotation_days must be between 0 and 365."
  }
}

variable "kms_key_arn" {
  description = "Customer-managed KMS key ARN for the storage volume, automated backups and the credentials secret. Empty falls back to the AWS-managed keys (aws/rds, aws/secretsmanager) — storage is encrypted either way. When set, iam_policy_json also grants the app kms:Decrypt on it so reading the secret still works."
  type        = string
  default     = ""

  validation {
    condition     = var.kms_key_arn == "" || can(regex("^arn:aws[a-z-]*:kms:", var.kms_key_arn))
    error_message = "kms_key_arn must be empty or a KMS key ARN (arn:aws:kms:...)."
  }
}

variable "db_parameters" {
  description = "Parameter-group entries applied to the instance. The defaults are the security baseline: TLS required, connections and disconnections logged. Entries are merged wholesale, so re-state the defaults if you override."
  type        = map(string)

  default = {
    "rds.force_ssl"      = "1"
    "log_connections"    = "1"
    "log_disconnections" = "1"
  }

  validation {
    # lookup with an unsafe sentinel, not try(..., "1"): an absent key used to PASS validation,
    # so a caller replacing the map wholesale could drop TLS enforcement by omission while the
    # access output still advertised sslmode = "require".
    condition     = lookup(var.db_parameters, "rds.force_ssl", "0") == "1"
    error_message = "db_parameters must include rds.force_ssl = \"1\" (the default carries it — re-state it when overriding): this module does not ship a configuration that accepts plaintext PostgreSQL connections."
  }
}

variable "backup_retention_days" {
  description = "Automated backup retention in days. Any value > 0 enables point-in-time restore; this module refuses 0."
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 35
    error_message = "backup_retention_days must be between 1 and 35 (0 would disable backups and point-in-time restore)."
  }
}

variable "backup_window" {
  description = "Daily UTC window for automated backups, e.g. \"03:00-04:00\". Null lets RDS choose."
  type        = string
  default     = null

  validation {
    condition     = var.backup_window == null || can(regex("^[0-2][0-9]:[0-5][0-9]-[0-2][0-9]:[0-5][0-9]$", var.backup_window))
    error_message = "backup_window must be null or hh:mm-hh:mm in UTC."
  }
}

variable "maintenance_window" {
  description = "Weekly UTC maintenance window, e.g. \"sun:05:00-sun:06:00\". Null lets RDS choose. Must not overlap backup_window."
  type        = string
  default     = null

  validation {
    condition     = var.maintenance_window == null || can(regex("^(mon|tue|wed|thu|fri|sat|sun):[0-2][0-9]:[0-5][0-9]-(mon|tue|wed|thu|fri|sat|sun):[0-2][0-9]:[0-5][0-9]$", var.maintenance_window))
    error_message = "maintenance_window must be null or ddd:hh:mm-ddd:hh:mm in UTC (lowercase day names)."
  }
}

variable "delete_automated_backups" {
  description = "Delete automated backups when the instance is destroyed. False keeps the retained backups for recovery."
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "Refuse to delete the instance. Defaults to the production-safe value; set false for demo teardown."
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Skip the final snapshot on destroy. Defaults to the production-safe value; set true for demo teardown."
  type        = bool
  default     = false
}

variable "iam_database_authentication_enabled" {
  description = "Allow IAM-token authentication to PostgreSQL, so applications need no stored password at all."
  type        = bool
  default     = true
}

variable "multi_az" {
  description = "Deploy a synchronous standby in a second AZ. Off by default because it roughly doubles instance cost; on is the production answer."
  type        = bool
  default     = false
}

variable "apply_immediately" {
  description = "Apply modifications at once rather than in the next maintenance window. Causes downtime for some changes."
  type        = bool
  default     = false
}

variable "cloudwatch_logs_exports" {
  description = "PostgreSQL log types shipped to CloudWatch Logs — the audit trail for connections and errors."
  type        = list(string)
  default     = ["postgresql", "upgrade"]

  validation {
    condition     = alltrue([for t in var.cloudwatch_logs_exports : contains(["postgresql", "upgrade"], t)])
    error_message = "cloudwatch_logs_exports for PostgreSQL accepts only \"postgresql\" and \"upgrade\"."
  }
}

variable "monitoring_role_arn" {
  description = "IAM role ARN for RDS Enhanced Monitoring. Null disables enhanced monitoring; this module never mints the role itself."
  type        = string
  default     = null

  validation {
    condition     = var.monitoring_role_arn == null || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/", var.monitoring_role_arn))
    error_message = "monitoring_role_arn must be null or an IAM role ARN."
  }
}

variable "monitoring_interval" {
  description = "Enhanced Monitoring granularity in seconds. Only used when monitoring_role_arn is set."
  type        = number
  default     = 60

  validation {
    condition     = contains([1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "monitoring_interval must be one of 1, 5, 10, 15, 30, 60."
  }
}

variable "performance_insights_enabled" {
  description = "Enable Performance Insights. Off by default because the db.t3.micro/small classes this module defaults to do not support it."
  type        = bool
  default     = false
}

variable "performance_insights_retention_days" {
  description = "Performance Insights retention. 7 is free tier; 731 is two years; other values must be a multiple of 31."
  type        = number
  default     = 7

  validation {
    condition     = var.performance_insights_retention_days == 7 || var.performance_insights_retention_days == 731 || var.performance_insights_retention_days % 31 == 0
    error_message = "performance_insights_retention_days must be 7, 731, or a multiple of 31."
  }
}

variable "secret_recovery_window_days" {
  description = "Secrets Manager recovery window for the credentials secret. Defaults to the production-safe 30 days; 0 deletes immediately and is the demo escape hatch (a non-zero window blocks reusing the same secret name)."
  type        = number
  default     = 30

  validation {
    condition     = var.secret_recovery_window_days == 0 || (var.secret_recovery_window_days >= 7 && var.secret_recovery_window_days <= 30)
    error_message = "secret_recovery_window_days must be 0 (immediate delete) or between 7 and 30."
  }
}

variable "db_subnet_group_name" {
  description = "Existing DB subnet group to place the instance in. Null uses the account's default subnet group; production should pass a private-subnet group."
  type        = string
  default     = null
}

variable "vpc_security_group_ids" {
  description = "Security groups to attach. Empty uses the VPC default security group, which permits no external ingress. This module never opens an ingress rule of its own."
  type        = list(string)
  default     = []
}
