# Opinionated small RDS Postgres: private, encrypted, TLS forced, backed up; master password generated here and stored only in Secrets Manager.

locals {
  # Parameter-group families are keyed on the major version only ("16.3" -> "postgres16").
  engine_major = split(".", var.engine_version)[0]

  use_cmk = var.kms_key_arn != ""
}

# Rotation clock: once the window elapses, the next apply sees a new id and the keeper regenerates the password.
resource "time_rotating" "master" {
  count = var.rotation_days > 0 ? 1 : 0

  rotation_days = var.rotation_days
}

# No special chars: RDS rejects '/', '@', '"' and spaces.
resource "random_password" "master" {
  length  = 24
  special = false

  # Null when rotation is off so existing passwords are untouched.
  keepers = var.rotation_days > 0 ? { rotated_at = one(time_rotating.master[*].id) } : null
}

# Final-snapshot identifiers must be unique per account; a state-stable suffix survives destroy/recreate cycles.
resource "random_id" "final_snapshot" {
  byte_length = 4
}

resource "aws_secretsmanager_secret" "master" {
  name        = "${var.name}-db-credentials"
  description = "Master credentials for the ${var.name} RDS PostgreSQL instance (managed by modules/aws/database)."
  kms_key_id  = local.use_cmk ? var.kms_key_arn : null

  recovery_window_in_days = var.secret_recovery_window_days

  tags = var.tags
}

# Written after the instance exists so host/port are real.
resource "aws_secretsmanager_secret_version" "master" {
  secret_id = aws_secretsmanager_secret.master.id
  secret_string = jsonencode({
    engine   = "postgres"
    username = var.master_username
    password = random_password.master.result
    host     = aws_db_instance.this.address
    port     = aws_db_instance.this.port
    dbname   = var.database_name
    sslmode  = "require"
  })
}

# rds.force_ssl is the only way to make TLS mandatory rather than merely offered.
resource "aws_db_parameter_group" "this" {
  # name_prefix + create_before_destroy: a family change forces replacement, and a fixed name would
  # collide with the group still attached to the running instance.
  name_prefix = "${var.name}-pg${local.engine_major}-"
  family      = "postgres${local.engine_major}"
  description = "Security baseline for ${var.name}: TLS required, connection logging on (managed by modules/aws/database)."

  dynamic "parameter" {
    for_each = var.db_parameters

    content {
      name  = parameter.key
      value = parameter.value
      # pending-reboot is accepted for both static and dynamic parameters; "immediate" is not.
      apply_method = "pending-reboot"
    }
  }

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "this" {
  identifier        = var.name
  engine            = "postgres"
  engine_version    = var.engine_version
  instance_class    = var.instance_class
  allocated_storage = var.allocated_storage_gb
  storage_type      = var.storage_type

  db_name  = var.database_name
  username = var.master_username
  password = random_password.master.result

  parameter_group_name = aws_db_parameter_group.this.name

  publicly_accessible = false # non-negotiable: private only
  storage_encrypted   = true
  kms_key_id          = local.use_cmk ? var.kms_key_arn : null

  db_subnet_group_name   = var.db_subnet_group_name
  vpc_security_group_ids = length(var.vpc_security_group_ids) > 0 ? var.vpc_security_group_ids : null

  # Retention > 0 is what makes point-in-time restore possible at all.
  backup_retention_period  = var.backup_retention_days
  backup_window            = var.backup_window
  maintenance_window       = var.maintenance_window
  copy_tags_to_snapshot    = true
  delete_automated_backups = var.delete_automated_backups

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.name}-final-${random_id.final_snapshot.hex}"

  iam_database_authentication_enabled = var.iam_database_authentication_enabled
  auto_minor_version_upgrade          = true
  multi_az                            = var.multi_az
  apply_immediately                   = var.apply_immediately

  enabled_cloudwatch_logs_exports = var.cloudwatch_logs_exports

  # Enhanced monitoring needs a pre-existing service role; off unless the caller supplies one.
  monitoring_role_arn = var.monitoring_role_arn
  monitoring_interval = var.monitoring_role_arn == null ? 0 : var.monitoring_interval

  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_kms_key_id       = var.performance_insights_enabled && local.use_cmk ? var.kms_key_arn : null
  performance_insights_retention_period = var.performance_insights_enabled ? var.performance_insights_retention_days : null

  tags = var.tags
}
