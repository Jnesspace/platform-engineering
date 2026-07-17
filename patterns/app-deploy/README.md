# app-deploy — the k8s deploy rung (runs what app-factory vended)

A Spacelift "deploy" stack runs this root against the app team's cluster: it
takes the app image plus [`app-factory`](../app-factory)'s outputs and turns
them into a running workload — Namespace, ServiceAccount, Deployment, Service.
The developer still touches nothing but their repo.

```
app-factory outputs  ──►  app-deploy (kubernetes)  ──►  Deployment runs var.image
  app_role_arn ────────────► ServiceAccount annotation (IRSA)
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

## IRSA: how the pod gets the role

The ServiceAccount's `eks.amazonaws.com/role-arn` annotation binds the pod to
the vended `app_role_arn` — the pod's tokens are exchanged for that role, so it
can read exactly the resources the shopping list ordered. When a real cluster
exists, the app role's trust policy must point at the EKS cluster's OIDC
provider; today app-factory ships EC2 trust as the placeholder (see its
[`iam.tf`](../app-factory/iam.tf)).

## No static credentials

The pod receives only *references* — bucket name, secret ARN, region — as env
vars. It fetches the secret value from Secrets Manager at runtime via the role.
No access keys, no secret values in manifests or state.

## Try it (no apply needed)

```sh
terraform init -backend=false
terraform validate
```
