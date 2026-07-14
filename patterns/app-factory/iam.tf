# "IAM and all those things": every AWS module emits an iam_policy_json scoped
# to exactly the resource it created. The engine attaches each as an inline
# policy on ONE app role, so the app can reach precisely what it ordered —
# nothing else.
#
# Keys come from the shopping list (known at plan); the policy JSON embeds
# resource ARNs (known only after apply) — so we key the for_each by resource,
# never by the policy content, and skip compute (it needs no data-plane policy).

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

  # EC2 trust as the simple default; the later k8s rung swaps this for
  # IRSA / EKS Pod Identity trust so the app's pods assume the role.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# One inline policy per provisioned resource, each the module's least-privilege
# grant. Sids only need to be unique within a policy, so no re-Sid'ing needed.
resource "aws_iam_role_policy" "app" {
  for_each = local.app_policies

  name   = "${local.app_name}-${each.key}"
  role   = aws_iam_role.app.id
  policy = each.value
}
