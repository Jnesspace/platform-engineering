# schedules — Spacelift scheduling primitives

Small self-contained references, one per scheduling resource. Attach any of
them to a stack you already run; none of these create stacks themselves.

| subdir | Spacelift resource | when to use |
|---|---|---|
| [`secret-rotation/`](secret-rotation/) | `spacelift_scheduled_run` | **Flagship.** Re-apply a service stack on a cron so `time_rotating`-keyed secrets (see `rotation_days` on `modules/aws/{secrets,database}`) regenerate once the window elapses. |
| [`scheduled-run/`](scheduled-run/) | `spacelift_scheduled_run` | Nightly/cron tracked run of a stack — refresh data sources, roll AMIs, re-converge. |
| [`scheduled-task/`](scheduled-task/) | `spacelift_scheduled_task` | Arbitrary command in the stack's workspace on a cron (cleanup scripts, `terraform apply -destroy`, CLI calls). |
| [`ephemeral-ttl/`](ephemeral-ttl/) | `spacelift_scheduled_delete_stack` | Auto-teardown of ephemeral envs: delete the stack (and optionally its resources) at a timestamp / after a TTL. |
| [`drift-detection/`](drift-detection/) | `spacelift_drift_detection` | Detect drift on a cron; optionally reconcile with a tracked run. |

## Try it (no apply needed)

```sh
terraform init -backend=false
terraform validate
```
