##############################################################################
# object-storage (AWS) — an opinionated private S3 bucket.
#
# Opinions baked in: all public access blocked, versioning on. Consumers get
# a least-privilege IAM policy (iam_policy_json output) scoped to this bucket
# only — the app-factory attaches it to the app role.
##############################################################################

resource "aws_s3_bucket" "this" {
  bucket        = var.name
  force_destroy = var.force_destroy
  tags          = var.tags
}

# Non-negotiable: nothing in this bucket is ever public.
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Versioning on by default: cheap insurance against accidental overwrites.
resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}
