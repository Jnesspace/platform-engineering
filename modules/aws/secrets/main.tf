# Opinionated Secrets Manager secret; value optionally seeded, otherwise written out-of-band so it never transits Terraform.

locals {
  use_cmk = var.kms_key_arn != ""
}

resource "aws_secretsmanager_secret" "this" {
  name        = var.name
  description = "Application secret ${var.name} (managed by modules/aws/secrets)."
  kms_key_id  = local.use_cmk ? var.kms_key_arn : null

  # A non-zero window is the undo button for an accidental delete; it also reserves the name.
  recovery_window_in_days = var.recovery_window_in_days

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "initial" {
  count = var.rotation_days == 0 && var.initial_value != "" ? 1 : 0

  secret_id     = aws_secretsmanager_secret.this.id
  secret_string = var.initial_value
}

# Rotation clock: once the window elapses, the next apply sees a new id and the keeper forces a fresh value.
resource "time_rotating" "rotation" {
  count = var.rotation_days > 0 ? 1 : 0

  rotation_days = var.rotation_days
}

resource "random_password" "rotating" {
  count = var.rotation_days > 0 ? 1 : 0

  length  = var.generated_value_length
  special = false

  keepers = {
    rotated_at = time_rotating.rotation[0].id
  }
}

resource "aws_secretsmanager_secret_version" "rotating" {
  count = var.rotation_days > 0 ? 1 : 0

  secret_id     = aws_secretsmanager_secret.this.id
  secret_string = random_password.rotating[0].result
}

# Belt to the identity policy's braces: even a mis-scoped role cannot read this over plaintext HTTP.
resource "aws_secretsmanager_secret_policy" "this" {
  count = var.enforce_tls_resource_policy ? 1 : 0

  secret_arn = aws_secretsmanager_secret.this.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyNonTLSAccess"
        Effect    = "Deny"
        Principal = "*"
        Action    = "secretsmanager:*"
        Resource  = "*"
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
    ]
  })
}
