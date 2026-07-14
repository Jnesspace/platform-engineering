output "id" {
  description = "ARN of the secret (the primary AWS identifier)."
  value       = aws_secretsmanager_secret.this.arn
}

output "name" {
  description = "Actual secret name created."
  value       = aws_secretsmanager_secret.this.name
}

output "endpoint" {
  description = "No network endpoint for a secret."
  value       = ""
}

output "access" {
  description = "How to reach this resource (uniform shape across primitives)."
  value = {
    secret_ref = aws_secretsmanager_secret.this.arn
    name       = aws_secretsmanager_secret.this.name
  }
}

# Read-only grant on exactly this secret: fetch the value, describe metadata.
# No List*, no write, no other secrets.
output "iam_policy_json" {
  description = "Least-privilege IAM policy: GetSecretValue + DescribeSecret on this secret only."
  value = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadThisSecret"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Resource = aws_secretsmanager_secret.this.arn
      },
    ]
  })
}
