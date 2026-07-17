# drift-detection — detect (and optionally reconcile) on a cron

Runs proposed-run drift checks on a cron; drifted stacks surface in Spacelift.
With `reconcile = true` a tracked run is triggered to converge back — pair
that with an approval policy if unattended re-applies are too aggressive.
Read-only by default, which is what makes it the right tool where
[`../scheduled-run/`](../scheduled-run/) would be a blunt re-apply.

```sh
terraform init -backend=false
terraform validate
```
