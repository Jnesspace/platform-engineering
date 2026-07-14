# Roles — reusable custom role definitions

The requester/approver split from [`docs/hardening-backlog.md`](../docs/hardening-backlog.md)
item 2: no single role holds both `RUN_TRIGGER` and `RUN_CONFIRM`, so the
person who triggers a run can never be the one who approves it. Attach via
`spacelift_role_attachment` (user / IdP group / stack, Space-scoped).

| role | actions | use |
|---|---|---|
| `requester` | `SPACE_READ`, `RUN_TRIGGER` | team members who order runs |
| `approver` | `SPACE_READ`, `RUN_CONFIRM` | leads/reviewers who sign off at the confirm gate |
| `reader` | `SPACE_READ` | audit / observers |
| `consumer` | `SPACE_READ`, `RUN_TRIGGER`, `RUN_CONFIRM` | the current combined role — self-approvable, for comparison only |
