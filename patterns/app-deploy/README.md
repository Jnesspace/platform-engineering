# app-deploy — the k8s deploy rung (runs what app-factory vended)

A Spacelift "deploy" stack runs this root against the app team's cluster: it
takes the app image plus [`app-factory`](../app-factory)'s outputs and turns
them into a running workload — Namespace, ServiceAccount, Deployment, Service,
and a default-deny NetworkPolicy. The developer still touches nothing but their
repo.

```
app-factory outputs  ──►  app-deploy (kubernetes)  ──►  Deployment runs var.image
  app_role_arn ────────────► ServiceAccount annotation (IRSA)
  app_role_trust ──────────► namespace / ServiceAccount names the role's `sub` is pinned to
  resource_access ─────────► container env (BUCKET_NAME, SECRET_ARN, AWS_REGION)
```

## Consuming app-factory (Spacelift stack dependency)

Wire the deploy stack downstream of the factory stack and map outputs to
`TF_VAR_*` inputs:

```hcl
resource "spacelift_stack_dependency" "factory_to_deploy" {
  stack_id            = spacelift_stack.app_deploy.id
  depends_on_stack_id = spacelift_stack.app_factory.id
}

resource "spacelift_stack_dependency_reference" "app_role_arn" {
  stack_dependency_id = spacelift_stack_dependency.factory_to_deploy.id
  output_name         = "app_role_arn"
  input_name          = "TF_VAR_app_role_arn"
}
```

`resource_access` is a map, so each reference carries one scalar: point
references at `resource_access["object_storage/<name>"].bucket` and
`resource_access["secrets/<name>"].secret_ref` (flat convenience outputs on the
factory, or set them by hand) to fill `TF_VAR_bucket` / `TF_VAR_secret_arn`.

**Keep the names in step.** The app role's trust policy pins the OIDC `sub` to
one exact `system:serviceaccount:<namespace>:<serviceaccount>`. This root
creates namespace `var.namespace` (default `app_name`) and ServiceAccount
`app_name`; the factory's `app_role_trust` output publishes what it pinned. If
you override `TF_VAR_namespace` here, override `TF_VAR_k8s_namespace` on the
factory to match — otherwise STS returns AccessDenied. The `irsa_subject`
output of this root and `app_role_trust.oidc_sub` of the factory must be
identical.

## IRSA: how the pod gets the role

The ServiceAccount's `eks.amazonaws.com/role-arn` annotation binds the pod to
the vended `app_role_arn`, and app-factory's role trusts the cluster's OIDC
provider for **that ServiceAccount only** — supply the cluster's provider ARN as
`TF_VAR_eks_oidc_provider_arn` on the factory stack. No wildcards: a
`StringLike` `sub` would hand this role to every pod in the cluster.

The credential is a projected service-account token, and this root projects it
**explicitly** rather than leaving it to the EKS pod-identity webhook:

| | volume | audience | Kubernetes API token in the pod? |
|---|---|---|---|
| `project_irsa_token = true` (default) | declared here as `aws-iam-token`, mounted read-only at `/var/run/secrets/eks.amazonaws.com/serviceaccount` | `sts.amazonaws.com` | **no** — `automountServiceAccountToken` is false |
| `project_irsa_token = false` | injected by the pod-identity webhook | `sts.amazonaws.com` | yes — the webhook's patch needs the automount machinery |

That is the whole reason the default path exists. `automountServiceAccountToken:
false` on its own **breaks IRSA** — with no volumes on the pod the webhook's
patch has nothing to append to, and the token file never appears. Declaring the
volume ourselves (same name, so the webhook sees it and skips) plus
`AWS_ROLE_ARN` / `AWS_WEB_IDENTITY_TOKEN_FILE` (which the webhook also treats as
"already handled") lets us drop the Kubernetes API credential while keeping the
AWS one. The token the pod holds is scoped to the `sts.amazonaws.com` audience,
so it is useless against the API server.

## Pod hardening

Applied by default; every control has a variable, and the default is the secure
value.

- Namespace carries `pod-security.kubernetes.io/{enforce,audit,warn} =
  restricted`, so admission enforces the posture even for anything else landing
  in this namespace.
- Pod: `runAsNonRoot`, `runAsUser`/`runAsGroup`/`fsGroup` 10001,
  `seccompProfile: RuntimeDefault`, `enableServiceLinks: false`.
- Container: `allowPrivilegeEscalation: false`, `privileged: false`,
  `readOnlyRootFilesystem: true`, `capabilities.drop: ["ALL"]`,
  `seccompProfile: RuntimeDefault`. An emptyDir supplies writable `/tmp`.
- CPU and memory **requests and limits** on every container.
- Liveness and readiness probes (`/healthz`, `/readyz`); set either path to `""`
  to fall back to a TCP connect on the container port.
- `container_port` must be >= 1024 — with all capabilities dropped the process
  cannot bind a privileged port.

## Network policy

Two objects, both gated on `enable_network_policy` (default true — only disable
it on a cluster whose CNI cannot enforce policy, where the objects would be
false assurance):

1. `default-deny-all` — empty pod selector, `Ingress` + `Egress`. Nothing in the
   namespace talks to anything.
2. `<app>-allow` — re-opens exactly: ingress on the container port from the same
   namespace (plus any namespace selectors in `ingress_namespace_labels`),
   egress to DNS in `kube-system` (53/UDP + 53/TCP), and egress on 443/TCP to
   `egress_cidr` **minus `169.254.169.254/32`** — so the pod can reach STS, S3
   and Secrets Manager but cannot reach IMDS and borrow the node's instance role
   in place of its own scoped one.

## No static credentials

The pod receives only *references* — bucket name, secret ARN, region — as env
vars. It fetches the secret value from Secrets Manager at runtime via the role.
No access keys, no secret values in manifests or state.

## Try it (no apply needed)

```sh
terraform init -backend=false
terraform validate
```
