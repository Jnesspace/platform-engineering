# secret-rotation — scheduled re-apply as the rotation trigger

Terraform never rotates a secret on its own: a `time_rotating`-keyed value only
regenerates when a run happens **after** the rotation window elapses. This
pattern supplies that run — one `spacelift_scheduled_run` that re-applies the
service stack on a cron (default: weekly, Sunday 03:00).

## The mechanism, end to end

1. **Opt in on the module.** Set the optional `rotation_days` input on the
   `modules/aws/secrets` (or `modules/aws/database`) call inside the service
   stack. That keys the stored value to a `time_rotating` keeper.
2. **Nothing happens until a run.** Once `rotation_days` elapses, the keeper is
   stale — but only the *next plan* notices.
3. **This schedule is the next plan.** The cron re-apply picks up the expired
   keeper, generates a fresh value, and writes it to Secrets Manager / the DB
   password. Runs inside the window are no-op applies.

Pick a cron at least as frequent as your shortest `rotation_days`, so a secret
is never stale longer than one schedule interval past its window.

## Notes

- The scheduled run is a normal **tracked run**: approval policies apply, so
  either auto-deploy the stack or exempt these runs via policy for unattended
  rotation.
- Imperative alternative (AWS-native rotation lambdas): a
  `spacelift_scheduled_task` running
  `aws secretsmanager rotate-secret --secret-id <id>` — see
  [`../scheduled-task/`](../scheduled-task/).

## Try it (no apply needed)

```sh
terraform init -backend=false
terraform validate
```
