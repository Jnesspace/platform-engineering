# scheduled-task — arbitrary command on a cron

Runs a single command inside the stack's workspace — same image, env, and
cloud credentials as a normal run, so CLI calls (e.g. `aws secretsmanager
rotate-secret ...`) just work. Use for imperative jobs that don't belong in
state: cleanup scripts, cache warms, native rotation kicks. `every` accepts
multiple cron expressions; a one-shot `at` (unix timestamp) is the alternative.

```sh
terraform init -backend=false
terraform validate
```
