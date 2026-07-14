# Blueprints — the non-dev / ticketing path

**Same modules, filled via a form.** This is the dual-purpose proof for
[`modules/`](../modules): a developer orders a primitive through the
app-factory shopping list; a non-developer (or a ticket) orders the *identical*
primitive through a Spacelift Blueprint form. One opinionated implementation,
two front doors — the guardrails (safe defaults, least-privilege access hooks)
travel with the module, not the entry point.

| blueprint | creates | inputs |
|---|---|---|
| [`object-storage.yaml`](object-storage.yaml) | S3 bucket via `modules/aws/object-storage` | bucket_name, team, force_destroy |
| [`database.yaml`](database.yaml) | RDS PostgreSQL via `modules/aws/database` | db_name, team, instance_class |
| [`secrets.yaml`](secrets.yaml) | Secrets Manager secret via `modules/aws/secrets` | secret_name, team, initial_value |
| [`compute.yaml`](compute.yaml) | EC2 instance via `modules/aws/compute` | instance_name, team, instance_type |

This is rung 5 of the DevX ladder (golden path / ticketing done right): the
Blueprint sits *on top of* the same module catalog — it never becomes a second
implementation to keep in sync.
