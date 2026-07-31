# Aggregate each module's least-privilege iam_policy_json onto ONE app role; keyed by resource because the policy JSON embeds ARNs unknown at plan. Trust is IRSA-first, with the `sub` pinned to the one namespace/ServiceAccount app-deploy creates — a wildcard there would hand this role to every pod in the cluster.

locals {
  app_policies = merge(
    { for k, m in module.object_storage : "s3-${k}" => m.iam_policy_json },
    { for k, m in module.secrets : "secret-${k}" => m.iam_policy_json },
    { for k, m in module.database : "db-${k}" => m.iam_policy_json },
  )

  # Must mirror patterns/app-deploy exactly: namespace = var.namespace or app_name, ServiceAccount = app_name.
  k8s_namespace       = var.k8s_namespace != "" ? var.k8s_namespace : local.app_name
  k8s_service_account = var.k8s_service_account != "" ? var.k8s_service_account : local.app_name

  # arn:aws:iam::<acct>:oidc-provider/<issuer host> -> <issuer host>, which prefixes both IRSA condition keys.
  oidc_arn_parts = split(":oidc-provider/", var.eks_oidc_provider_arn)
  eks_oidc_host  = length(local.oidc_arn_parts) == 2 ? local.oidc_arn_parts[1] : ""

  irsa_sub = "system:serviceaccount:${local.k8s_namespace}:${local.k8s_service_account}"

  # StringEquals on both keys, never StringLike; `aud` is sts.amazonaws.com, the audience the projected token is minted for.
  irsa_trust = {
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AssumeViaClusterOidc"
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = var.eks_oidc_provider_arn }
      Condition = {
        StringEquals = {
          "${local.eks_oidc_host}:aud" = "sts.amazonaws.com"
          "${local.eks_oidc_host}:sub" = local.irsa_sub
        }
      }
    }]
  }

  # Kept for the non-k8s case (the app runs on the compute primitive), but it has to be opted into.
  ec2_trust = {
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AssumeViaEc2"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  }
}

# Plan-time gate so nobody ends up with a role no workload can assume: IRSA without a cluster OIDC provider, or an OIDC provider that will never be used.
resource "terraform_data" "trust_guard" {
  input = var.trust_mode

  lifecycle {
    precondition {
      condition     = var.trust_mode != "irsa" || local.eks_oidc_host != ""
      error_message = "trust_mode is \"irsa\" but eks_oidc_provider_arn is not an IAM OIDC provider ARN. Get it with: aws iam list-open-id-connect-providers, or derive it from `aws eks describe-cluster --name <cluster> --query cluster.identity.oidc.issuer`. Set trust_mode = \"ec2\" only if the app runs on the compute primitive instead of Kubernetes."
    }
    precondition {
      condition     = var.trust_mode != "irsa" || can(regex("^oidc\\.eks\\.[a-z0-9-]+\\.amazonaws\\.com/id/[A-Za-z0-9]+$", local.eks_oidc_host))
      error_message = "eks_oidc_provider_arn '${var.eks_oidc_provider_arn}' does not look like an EKS cluster OIDC provider (expected .../oidc-provider/oidc.eks.<region>.amazonaws.com/id/<hash>). Pinning the trust to the wrong issuer silently produces an unassumable role."
    }
    precondition {
      # The sub has to match what app-deploy actually creates, and both halves must be legal DNS-1123 labels.
      condition     = var.trust_mode != "irsa" || (can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", local.k8s_namespace)) && can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", local.k8s_service_account)))
      error_message = "IRSA sub would be '${local.irsa_sub}', but the namespace and ServiceAccount must be DNS-1123 labels (lowercase alphanumeric/hyphen, <= 63 chars). Set k8s_namespace / k8s_service_account to match app-deploy's namespace and app_name."
    }
    precondition {
      condition     = var.trust_mode != "ec2" || var.eks_oidc_provider_arn == ""
      error_message = "trust_mode is \"ec2\" but eks_oidc_provider_arn is set — the resulting role trusts EC2 only and no pod could assume it. Set trust_mode = \"irsa\", or clear eks_oidc_provider_arn."
    }
  }
}

resource "aws_iam_role" "app" {
  depends_on = [terraform_data.trust_guard]

  name        = "${local.app_name}-app"
  description = "Least-privilege role for ${local.app_name}, aggregating every ordered resource's grant (trust: ${var.trust_mode})."
  tags        = local.tags

  assume_role_policy   = var.trust_mode == "irsa" ? jsonencode(local.irsa_trust) : jsonencode(local.ec2_trust)
  permissions_boundary = var.app_role_permissions_boundary_arn != "" ? var.app_role_permissions_boundary_arn : null
}

# Sids only need to be unique within each policy, so no re-Sid'ing needed.
resource "aws_iam_role_policy" "app" {
  for_each = local.app_policies

  name   = "${local.app_name}-${each.key}"
  role   = aws_iam_role.app.id
  policy = each.value
}
