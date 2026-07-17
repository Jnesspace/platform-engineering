# jimmy-app

What an app repo looks like on the converged-onboarding rung: the developer
ships their code (`Dockerfile`) plus one shopping list (`platform.yaml`), and
`patterns/app-factory` turns that list into cloud resources — S3 bucket,
secret, Postgres — with a single least-privilege IAM role wired to exactly
those resources.

The Kubernetes deploy layer that consumes the engine's `resource_access`
output (and assumes the app role) lives in
[`patterns/app-deploy`](../../patterns/app-deploy) — see [deploy.md](deploy.md).
