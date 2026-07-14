# Aggregate each module's least-privilege iam_policy_json onto ONE app role; keyed by resource because the policy JSON embeds ARNs unknown at plan.

locals {
  app_policies = merge(
    { for k, m in module.object_storage : "s3-${k}" => m.iam_policy_json },
    { for k, m in module.secrets : "secret-${k}" => m.iam_policy_json },
    { for k, m in module.database : "db-${k}" => m.iam_policy_json },
  )
}

resource "aws_iam_role" "app" {
  name = "${local.app_name}-app"
  tags = local.tags

  # EC2 trust as the simple default; a later k8s rung swaps in IRSA / Pod Identity trust.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Sids only need to be unique within each policy, so no re-Sid'ing needed.
resource "aws_iam_role_policy" "app" {
  for_each = local.app_policies

  name   = "${local.app_name}-${each.key}"
  role   = aws_iam_role.app.id
  policy = each.value
}
