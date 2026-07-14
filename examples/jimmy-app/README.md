# jimmy-app

What an app repo looks like on the converged-onboarding rung: the developer
ships their code (`Dockerfile`) plus one shopping list (`platform.yaml`), and
`patterns/app-factory` turns that list into cloud resources — S3 bucket,
secret, Postgres — with a single least-privilege IAM role wired to exactly
those resources.

The Kubernetes deploy layer that would consume the engine's `resource_access`
output (and assume the app role) is a **later rung** — deliberately out of
scope here.
