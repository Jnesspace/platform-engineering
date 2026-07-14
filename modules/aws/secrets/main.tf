##############################################################################
# secrets (AWS) — an opinionated Secrets Manager secret.
#
# Creates the secret shell; optionally seeds a first version when
# var.initial_value is set (e.g. by a Blueprint form). Otherwise the value is
# written out-of-band (console/CLI) so it never has to transit Terraform.
##############################################################################

resource "aws_secretsmanager_secret" "this" {
  name        = var.name
  description = "Application secret ${var.name} (managed by modules/aws/secrets)."
  tags        = var.tags
}

# Seed version only when an initial value was provided.
resource "aws_secretsmanager_secret_version" "initial" {
  count = var.initial_value != "" ? 1 : 0

  secret_id     = aws_secretsmanager_secret.this.id
  secret_string = var.initial_value
}
