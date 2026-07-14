output "id" {
  description = "ARN of the DB instance (the primary AWS identifier)."
  value       = aws_db_instance.this.arn
}

output "name" {
  description = "Actual RDS instance identifier created."
  value       = aws_db_instance.this.identifier
}

output "endpoint" {
  description = "Connection endpoint (host:port)."
  value       = aws_db_instance.this.endpoint
}

output "access" {
  description = "How to reach this resource. Credentials live in secret_ref, never in outputs."
  value = {
    host       = aws_db_instance.this.address
    port       = aws_db_instance.this.port
    dbname     = var.database_name
    username   = var.master_username
    secret_ref = aws_secretsmanager_secret.master.arn
  }
}

# Apps never get RDS API permissions — only a read on the credentials secret.
output "iam_policy_json" {
  description = "Least-privilege IAM policy: GetSecretValue on this database's credentials secret only."
  value = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadDbCredentials"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = aws_secretsmanager_secret.master.arn
      },
    ]
  })
}
