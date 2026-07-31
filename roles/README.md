# Roles — the requester/approver split, defined *and bound*

[`docs/hardening-backlog.md`](../docs/hardening-backlog.md) item 2. No single role holds both
`RUN_TRIGGER` and `RUN_CONFIRM`, and this root also **binds** them, because an unattached role
enforces nothing — which is how item 2 stayed open while the role definitions already existed.

| role | actions | use |
|---|---|---|
| `requester` | `SPACE_READ`, `RUN_TRIGGER` | team members who order runs |
| `approver` | `SPACE_READ`, `RUN_CONFIRM` | leads/reviewers who sign off at the confirm gate |
| `reader` | `SPACE_READ` | audit / observers |

The old combined `consumer` role (`SPACE_READ` + `RUN_TRIGGER` + `RUN_CONFIRM`) has been **removed**,
not deprecated. It made every confirm gate self-approvable, and a role that exists is a role someone
attaches.

## The two halves of the control

| half | where | what it stops |
|---|---|---|
| role split + disjoint bindings | this root | one identity cannot both trigger and confirm |
| `policies/approval/deny-self-approval.rego` | `bootstrap/governance` | a run whose only approval came from its triggerer |

Both are needed: RBAC stops the *permission*, the APPROVAL policy stops the *decision*. Neither is
sufficient alone — two people in the same group still need the policy to force a second signature.

## Who runs it, with what, in what order

Platform admin, **root-admin API key** (you cannot grant a role you do not hold), **after** the
`bootstrap/*` roots — `governed_spaces` takes the Space IDs they output.

```sh
cp terraform.tfvars.example terraform.tfvars   # then edit
export SPACELIFT_API_KEY_ENDPOINT=https://<your-account>.app.spacelift.io
export SPACELIFT_API_KEY_ID=...      # root-admin key
export SPACELIFT_API_KEY_SECRET=...
terraform init && terraform apply
```

`requester_groups` and `approver_groups` are IdP group names resolved through
`data.spacelift_idp_group_mapping`, so no ULID is hardcoded. A group listed in both fails the plan
(`terraform_data.separation_of_duties`) — Terraform 1.5 cannot compare two variables inside a
`validation` block, so the check lives in a precondition.

## Scope note

Spacelift role attachments are **Space-scoped**; there is no stack-scoped binding for a human
subject (`api_key_id` / `idp_group_mapping_id` / `stack_id` / `user_id` are mutually exclusive — a
`stack_id` attachment makes the *stack* the subject, which is the elevation mechanism in
`bootstrap/*`). To confine a team to a single entry point, give that Space exactly one stack, the way
`bootstrap/nonadmin-launcher` puts only the engine in the `platform` Space.
