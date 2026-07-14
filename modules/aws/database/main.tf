# Opinionated small RDS Postgres: private, encrypted, master password generated here and stored only in Secrets Manager.

# No special chars: RDS rejects '/', '@', '"' and spaces.
resource "random_password" "master" {
  length  = 24
  special = false
}

resource "aws_secretsmanager_secret" "master" {
  name        = "${var.name}-db-credentials"
  description = "Master credentials for the ${var.name} RDS PostgreSQL instance (managed by modules/aws/database)."
  tags        = var.tags
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
