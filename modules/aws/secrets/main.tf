# Opinionated Secrets Manager secret; value optionally seeded, otherwise written out-of-band so it never transits Terraform.

resource "aws_secretsmanager_secret" "this" {
  name        = var.name
  description = "Application secret ${var.name} (managed by modules/aws/secrets)."
  tags        = var.tags
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

  length  = 32
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
