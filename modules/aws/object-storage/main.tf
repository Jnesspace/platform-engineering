# Opinionated private S3 bucket: public access blocked, ACLs off, TLS required, encrypted at rest, versioned; iam_policy_json output grants this bucket only.

locals {
  # Empty kms_key_arn means SSE-S3 (AWS-managed key); a CMK switches the bucket to SSE-KMS.
  use_cmk = var.kms_key_arn != ""
}

resource "aws_s3_bucket" "this" {
  bucket        = var.name
  force_destroy = var.force_destroy
  tags          = var.tags
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# BucketOwnerEnforced disables ACLs outright, so an identity policy is the only access path.
resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = local.use_cmk ? "aws:kms" : "AES256"
      kms_master_key_id = local.use_cmk ? var.kms_key_arn : null
    }

    # S3 Bucket Keys collapse per-object KMS calls; a no-op under SSE-S3.
    bucket_key_enabled = local.use_cmk
  }
}

# A bucket policy is the only place TLS can be *required* rather than merely available.
resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyNonTLSRequests"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.this.arn, "${aws_s3_bucket.this.arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
      {
        Sid       = "DenyOutdatedTLS"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.this.arn, "${aws_s3_bucket.this.arn}/*"]
        Condition = { NumericLessThan = { "s3:TlsVersion" = "1.2" } }
      },
    ]
  })

  # Order matters: the public access block must land before any policy is evaluated.
  depends_on = [aws_s3_bucket_public_access_block.this]
}

# Access logs go to a bucket the caller owns; a bucket must never log to itself.
resource "aws_s3_bucket_logging" "this" {
  count = var.access_log_bucket == "" ? 0 : 1

  bucket        = aws_s3_bucket.this.id
  target_bucket = var.access_log_bucket
  target_prefix = var.access_log_prefix != "" ? var.access_log_prefix : "s3-access-logs/${var.name}/"
}

# Versioning without expiry grows forever, and abandoned multipart parts are invisible but billable.
resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = var.abort_incomplete_multipart_upload_days
    }
  }

  rule {
    id     = "expire-noncurrent-versions"
    status = var.noncurrent_version_expiration_days > 0 ? "Enabled" : "Disabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = max(var.noncurrent_version_expiration_days, 1)
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}
