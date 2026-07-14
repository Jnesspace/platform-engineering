output "id" {
  description = "ARN of the bucket (the primary AWS identifier)."
  value       = aws_s3_bucket.this.arn
}

output "name" {
  description = "Actual bucket name created."
  value       = aws_s3_bucket.this.bucket
}

output "endpoint" {
  description = "Regional bucket domain name."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "access" {
  description = "How to reach this resource (uniform shape across primitives)."
  value = {
    bucket          = aws_s3_bucket.this.bucket
    arn             = aws_s3_bucket.this.arn
    regional_domain = aws_s3_bucket.this.bucket_regional_domain_name
  }
}

output "iam_policy_json" {
  description = "Least-privilege IAM policy granting app access to this bucket only."
  value = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = aws_s3_bucket.this.arn
      },
      {
        Sid      = "ObjectReadWriteDelete"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.this.arn}/*"
      },
    ]
  })
}
