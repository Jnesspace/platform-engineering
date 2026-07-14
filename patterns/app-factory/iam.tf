# "IAM and all those things": every AWS module emits an iam_policy_json scoped
# to exactly the resource it created. The engine aggregates them into ONE app
# role + ONE policy, so the app can reach precisely what it ordered — nothing
# else. (AWS path only; Azure/GCP modules expose role/scope data in `access`
# for their own RBAC wiring on a later rung.)

locals {
  aws_policy_docs = compact(concat(
    [for m in values(module.aws_object_storage) : m.iam_policy_json],
    [for m in values(module.aws_secrets) : m.iam_policy_json],
    [for m in values(module.aws_database) : m.iam_policy_json],
    [for m in values(module.aws_compute) : m.iam_policy_json], # compute emits "" — compact() drops it
  ))

  # Modules use fixed Sids, which would collide when the same primitive is
  # ordered twice — re-Sid every statement with a unique index.
  aws_statements = [
    for i, s in flatten([for doc in local.aws_policy_docs : jsondecode(doc).Statement]) :
    merge(s, { Sid = format("AppFactory%03d", i) })
  ]
}

resource "aws_iam_role" "app" {
  count = local.is_aws ? 1 : 0

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

resource "aws_iam_policy" "app" {
  count = local.is_aws && length(local.aws_statements) > 0 ? 1 : 0

  name = "${local.app_name}-app-access"
  tags = local.tags

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = local.aws_statements
  })
}

resource "aws_iam_role_policy_attachment" "app" {
  count = local.is_aws && length(local.aws_statements) > 0 ? 1 : 0

  role       = aws_iam_role.app[0].name
  policy_arn = aws_iam_policy.app[0].arn
}
