##############################################################################
# database (AWS) — an opinionated small RDS PostgreSQL instance.
#
# Opinions baked in: db.t3.micro / 20GB, never publicly accessible, storage
# encrypted, master password generated here and stored ONLY in Secrets
# Manager (it is never an input and never leaves state unencrypted paths).
# Apps read credentials via access.secret_ref; iam_policy_json grants exactly
# that one GetSecretValue.
##############################################################################

# Master password: generated, never supplied. No special chars — RDS rejects
# '/', '@', '"' and spaces, so alphanumerics keep it universally safe.
resource "random_password" "master" {
  length  = 24
  special = false
}

resource "aws_secretsmanager_secret" "master" {
  name        = "${var.name}-db-credentials"
  description = "Master credentials for the ${var.name} RDS PostgreSQL instance (managed by modules/aws/database)."
  tags        = var.tags
}

# Full connection bundle, written after the instance exists so host/port are
# real. Apps need only this secret + the policy from iam_policy_json.
resource "aws_secretsmanager_secret_version" "master" {
  secret_id = aws_secretsmanager_secret.master.id
  secret_string = jsonencode({
    engine   = "postgres"
    username = var.master_username
    password = random_password.master.result
    host     = aws_db_instance.this.address
    port     = aws_db_instance.this.port
    dbname   = var.database_name
  })
}

resource "aws_db_instance" "this" {
  identifier        = var.name
  engine            = "postgres"
  engine_version    = var.engine_version
  instance_class    = var.instance_class
  allocated_storage = var.allocated_storage_gb

  db_name  = var.database_name
  username = var.master_username
  password = random_password.master.result

  publicly_accessible = false # non-negotiable: private only
  storage_encrypted   = true
  skip_final_snapshot = true # small-tier default; flip for anything precious

  tags = var.tags
}
