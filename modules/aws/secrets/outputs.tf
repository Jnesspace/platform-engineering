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
  description = "How to reach this resource (uniform shape across primitives). References only — the value is never an output."
  value = {
    secret_ref  = aws_secretsmanager_secret.this.arn
    name        = aws_secretsmanager_secret.this.name
    kms_key_arn = var.kms_key_arn
  }
}

output "iam_policy_json" {
  description = "Least-privilege IAM policy: GetSecretValue + DescribeSecret on this secret only, plus kms:Decrypt on the CMK when one encrypts it."
  value = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid      = "ReadThisSecret"
          Effect   = "Allow"
          Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
          Resource = aws_secretsmanager_secret.this.arn
        },
      ],
      # A CMK-encrypted secret is unreadable without Decrypt on the key, however wide the Secrets Manager grant.
      local.use_cmk ? [
        {
          Sid      = "DecryptThisSecret"
          Effect   = "Allow"
          Action   = ["kms:Decrypt", "kms:DescribeKey"]
          Resource = var.kms_key_arn
        },
      ] : [],
    )
  })
}
