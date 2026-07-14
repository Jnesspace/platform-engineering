# Opinionated Secrets Manager secret; value optionally seeded, otherwise written out-of-band so it never transits Terraform.

resource "aws_secretsmanager_secret" "this" {
  name        = var.name
  description = "Application secret ${var.name} (managed by modules/aws/secrets)."
  tags        = var.tags
}

resource "aws_secretsmanager_secret_version" "initial" {
  count = var.initial_value != "" ? 1 : 0

  secret_id     = aws_secretsmanager_secret.this.id
  secret_string = var.initial_value
}
