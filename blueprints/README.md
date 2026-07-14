# Blueprints — the non-dev / ticketing path

**Same modules, filled via a form.** This is the dual-purpose proof for
[`modules/`](../modules): a developer orders a primitive through the
app-factory shopping list; a non-developer (or a ticket) orders the *identical*
primitive through a Spacelift Blueprint form. One opinionated implementation,
two front doors — the guardrails (safe defaults, least-privilege access hooks)
travel with the module, not the entry point.

| file | what it vends |
|---|---|
| [`object-storage.yaml`](object-storage.yaml) | an S3 bucket via `modules/aws/object-storage`, name/team/force_destroy as form fields |

This is rung 5 of the DevX ladder (golden path / ticketing done right): the
Blueprint sits *on top of* the same module catalog — it never becomes a second
implementation to keep in sync.
