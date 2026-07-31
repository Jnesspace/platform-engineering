# jimmy-app

What an app repo looks like on the converged-onboarding rung: the developer
ships their code (`Dockerfile`) plus one shopping list (`platform.yaml`), and
`patterns/app-factory` turns that list into cloud resources — S3 bucket,
secret, Postgres — with a single least-privilege IAM role wired to exactly
those resources.

`platform.yaml` carries only what jimmy-app gets to decide: which resources,
their names, its owning team, and per-resource options that can only *strengthen*
the posture (a platform CMK, secret rotation, a database standby). Anything that
weakens a default — `force_destroy`, `deletion_protection`, `skip_final_snapshot`,
a short secret recovery window — plus the `Environment` tag are set on the
Spacelift stack, which jimmy-app's repo cannot write to; app-factory fails the
plan if they appear here. See
[the schema](../../patterns/app-factory/README.md#shopping-list-schema-platformyaml).

The Kubernetes deploy layer that consumes the engine's `resource_access`
output (and assumes the app role) lives in
[`patterns/app-deploy`](../../patterns/app-deploy) — see [deploy.md](deploy.md).
