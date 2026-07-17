# scheduled-run — cron-triggered tracked run

Triggers a **tracked run** (plan → apply, approval policies honored) on a cron.
There is no plan-only mode on this resource — for read-only checks use
[`../drift-detection/`](../drift-detection/). Use this to re-converge nightly,
refresh data sources, or roll time-sensitive resources. `every` accepts
multiple cron expressions; a one-shot `at` (unix timestamp) is the alternative.

```sh
terraform init -backend=false
terraform validate
```
