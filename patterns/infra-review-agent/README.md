# infra-review agent — pipeline-embedded AI plan review (PoC)

A pattern root that vends a single Spacelift **context** carrying everything an
infrastructure review agent needs: the agent script (mounted file), its
configuration (environment variables), and the run wiring (`after_plan`
hooks). Any stack opts in with **one label** — no per-stack edits, no new
worker image, no VCS token.

The agent itself lives in [`agents/infra-review`](../../agents/infra-review/README.md):
a zero-dependency Node script that summarizes the plan, redacts likely
secrets, and asks an Anthropic model to review the change (security posture,
operational risk, cost, and — if you provide one — a deployment spec).

## The loop

```
stack labeled `infra-review` ─▶ PR opened ─▶ proposed run
                                                └─ after_plan: terraform show -json spacelift.plan
                                                └─ after_plan: node /mnt/workspace/infra-review/agent.mjs
                                                                  ├─ review printed into the run logs
                                                                  ├─ infrareview.custom.spacelift.json written
                                                                  │    → plan policies can act on the verdict
                                                                  └─ fail_on=findings → run fails on blocking findings
```

Because contexts attach across a whole Space, one label scales the agent to
every stack a team owns, and removing the label scales it back to zero.

## Usage

Apply this root from an administrative stack (or by hand), then label any
stack:

```hcl
resource "spacelift_stack" "app" {
  # ...
  labels = ["infra-review"]
}
```

On the next proposed run, the run logs gain an `infra-review report` section.

| Variable             | Default                   | Notes |
| -------------------- | ------------------------- | ----- |
| `anthropic_api_key`  | `""` (inert)              | Write-only `ANTHROPIC_API_KEY` on the context. Empty = agent logs a skip. |
| `model`              | `claude-sonnet-4-5`       | Anthropic model ID. |
| `run_types`          | `["PROPOSED"]`            | PR runs only. Add `TRACKED` or use `["ALL"]`. |
| `fail_on`            | `never`                   | `never` advisory · `findings` blocks on fail verdict / high+critical · `error` blocks when the review itself errors. |
| `spec` / `spec_file` | `""`                      | Deployment spec to verify against, inline or a repo-relative file. |
| `max_plan_bytes`     | `200000`                  | Raw-plan byte budget sent to the model. |
| `labels`             | `["autoattach:infra-review"]` | At least one `autoattach:` label required. |

The full per-variable config contract is documented in the
[agent README](../../agents/infra-review/README.md).

## Security notes

* **Plan content leaves the worker** — the plan goes to the Anthropic API
  after two independent redaction layers (Terraform sensitivity masks, then a
  credential/blob key denylist) and a byte cap. Over-redaction is deliberate;
  review what your plans contain before enabling, and prefer per-Space
  contexts for blast-radius control. The full threat model (spec-file
  containment, error-body policy, base-URL policy, untrusted-data prompt
  handling) lives in the [agent README](../../agents/infra-review/README.md).
* The API key is a write-only context variable and never appears in logs or
  state outputs. The agent only sends it to `https://` endpoints (loopback
  excepted for testing). A stack-level variable of the same name would
  override it (stack env beats context env) — deliberate, so a team can bring
  its own key.
* Default posture is advisory. Even `fail_on=findings` only fails the hook of
  that stack's run — it cannot touch anything else.
* Workers need `node >= 18`; without it the hook skips with a log line instead
  of failing runs.
* The mounted agent is `write_only = false` on purpose: it is code, and being
  able to diff the deployed checksum against this repo is a feature.

## Consuming example

[`examples/consuming-stack`](examples/consuming-stack/main.tf) is a minimal
stack root whose plan the agent can review end-to-end.

## PoC scope

This is a proof of concept: single `after_plan` stage, logs + custom-input as
the only outputs, no retries, no PR comments (workers hold no VCS token). The
shape is deliberate — "agent as a context" — so richer scheduling (other hook
stages, per-Space config, an eventual first-class agent-policy resource) is
additive rather than a redesign.
