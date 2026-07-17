# ephemeral-ttl — auto-teardown at a time or after a delay

Schedules stack deletion via `spacelift_scheduled_delete_stack`. The resource
takes a single unix timestamp (`at` — no cron), so this reference offers two
inputs: an explicit `delete_at`, or `ttl_hours` anchored at first apply via
`time_offset`. With `delete_resources = true` (the default here) the stack's
managed resources are destroyed first — the whole point for ephemeral
preview/test envs.

```sh
terraform init -backend=false
terraform validate
```
