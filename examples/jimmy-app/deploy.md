# Deploying jimmy-app

After [`patterns/app-factory`](../../patterns/app-factory) vends jimmy-app's
resources (bucket, secret, one app role), the
[`patterns/app-deploy`](../../patterns/app-deploy) stack runs jimmy-app's image
on Kubernetes with those wired in: the ServiceAccount assumes `app_role_arn`
via IRSA, and the bucket name / secret ARN arrive as env vars — the app reads
its secret from Secrets Manager at runtime, so no credentials ever land in the
repo, image, or manifests.
