# infra-review agent (PoC)

An infrastructure review agent that runs **inside the Spacelift worker** as an
`after_plan` hook. On each run it reviews the Terraform/OpenTofu plan with an
Anthropic model and writes the verdict into the run logs — and, optionally,
blocks the run.

The agent is a single zero-dependency Node script (`agent.mjs`, Node >= 18,
global `fetch`). It is delivered to workers by the
[`patterns/infra-review-agent`](../../patterns/infra-review-agent/README.md)
module: a Spacelift **context** that mounts this file at
`/mnt/workspace/infra-review/agent.mjs`, injects the config below, and carries
the hooks — so any stack opts in with one label, no per-stack edits.

## How a run looks

```
PR opened ─▶ proposed run starts ─▶ terraform plan
                                      └─ after_plan hook 1: terraform show -json spacelift.plan > /tmp/infra-review.plan.json
                                      └─ after_plan hook 2: node /mnt/workspace/infra-review/agent.mjs /tmp/infra-review.plan.json
                                                              ├─ run type not in INFRA_REVIEW_RUN_TYPES → skip
                                                              ├─ plan summarized + sensitive values redacted
                                                              ├─ Anthropic /v1/messages review
                                                              ├─ report printed to run logs
                                                              └─ infrareview.custom.spacelift.json written
```

## Configuration (context vars)

| Variable                     | Default                      | Meaning |
| ---------------------------- | ---------------------------- | ------- |
| `ANTHROPIC_API_KEY`          | — (required to call the API) | Anthropic API key. Write-only on the context. Without it the agent logs a skip and exits 0. |
| `INFRA_REVIEW_MODEL`         | `claude-sonnet-4-5`          | Model ID passed to the Messages API. |
| `INFRA_REVIEW_RUN_TYPES`     | `PROPOSED`                   | CSV of Spacelift run types to review, or `ALL`. `PROPOSED` = PR runs only. |
| `INFRA_REVIEW_FAIL_ON`       | `never`                      | `never` = advisory; `findings` = exit 1 (fail the run) on `fail` verdicts or high/critical findings; `error` = exit 1 when the review itself errors. |
| `INFRA_REVIEW_SPEC`          | —                            | Inline deployment spec the plan is verified against. |
| `INFRA_REVIEW_SPEC_FILE`     | —                            | Path to a spec file. Must be relative and stay inside the project root after `realpath`; absolute paths and traversal are rejected (the agent logs and continues without the spec). |
| `INFRA_REVIEW_MAX_PLAN_BYTES`| `200000`                     | Byte budget for the raw plan JSON sent to the model. |
| `ANTHROPIC_BASE_URL`         | `https://api.anthropic.com`  | Override for proxies/self-hosted gateways. Must be `https://`; `http://127.0.0.1` / `http://localhost` are allowed for local testing. Anything else = the agent refuses to send the key and skips. |

Spacelift itself injects `TF_VAR_spacelift_run_type` (`PROPOSED`, `TRACKED`,
`TASK`, ...) — that is the PR gate.

## Output contract

The model answers with strict JSON:

```json
{
  "verdict": "pass | warn | fail",
  "summary": "one or two sentences",
  "findings": [{ "severity": "info|low|medium|high|critical", "resource": "...", "title": "...", "detail": "...", "remediation": "..." }]
}
```

The agent prints a human-readable report to the run logs and writes
`infrareview.custom.spacelift.json` at the project root, so a plan policy can
act on the verdict via `input.third_party_metadata.custom.infrareview` — e.g.
deny when `verdict == "fail"` — without the agent itself deciding merge
outcomes.

## Security notes

* **Plan content leaves the worker.** The plan is sent to the Anthropic API
  after two independent redaction layers — but it is still your plan. Prefer
  per-Space contexts for blast-radius control, and review what your plans
  contain before enabling.
* **Redaction layer 1 — Terraform sensitivity masks.** Plans carry
  `before_sensitive`/`after_sensitive` masks on every resource change and
  output, `sensitive_values` masks (plus `sensitive_attributes` paths) in
  `planned_values`. These mark values sensitive even under generic key names —
  e.g. `random_password`'s `result`. The agent walks the mask trees and
  redacts the corresponding values before anything is serialized. Mask
  semantics: `true` redacts the whole sibling value, objects recurse matching
  keys, arrays recurse elements; unknown mask shapes redact conservatively.
* **Redaction layer 2 — key-name denylist.** Some fields are opaque
  credentials or blobs without any mask marking them, so exact key names
  (`result`, `value`, `data`, `binary_data`, `user_data`, `custom_data`),
  suffixes (`*_access_key`, `*_connection_string`), and a regex
  (`password|secret|token|private_key|api_key|credential|session|cookie`)
  redact regardless. **Tradeoff:** this over-redacts — e.g. every `data` map,
  sensitive or not, arrives as `[REDACTED]`. An over-redacted plan still
  reviews fine (the model sees structure, addresses, and non-sensitive
  values); an under-redacted one leaks. That asymmetry is deliberate.
* **Spec file containment.** `INFRA_REVIEW_SPEC_FILE` is resolved with
  `realpath` and must stay under the process cwd (the stack's project root).
  Absolute paths and `..` traversal are rejected, and symlinks pointing
  outside the root fail containment. The motivating target was
  `/proc/self/environ` — a worker env file that holds the API key — and any
  equivalent file the plan's author shouldn't get to upload.
* **API error bodies are never surfaced.** Non-2xx responses are reported as
  status code + content-type only. Response bodies can echo credentials or
  attacker-controlled text, so they are never logged and never persisted to
  the custom-input file.
* **Base URL policy.** The API key is only sent to an `https://` endpoint, or
  to `http://127.0.0.1` / `http://localhost` for local testing. Anything else
  and the agent refuses to send the key and skips (exit 0 unless
  `INFRA_REVIEW_FAIL_ON=error`).
* **Untrusted data + output hygiene.** The system prompt marks the plan and
  spec as untrusted data: the model is told not to follow instructions
  embedded in them and never to quote credential values. Model output is
  sanitized before printing/persisting — control characters (except `\n`) are
  stripped and fields are length-capped.
* The API key is a **write-only** context variable; it is never logged.
* Default posture is **advisory** (`INFRA_REVIEW_FAIL_ON=never`): the PoC
  cannot block a deploy unless you explicitly opt in per context.
* The runner image needs `node >= 18`. Without it the hook logs a skip and the
  run proceeds.

## Local development

```bash
npm run check   # syntax check
npm test        # smoke test against a stub Anthropic API (no key needed)
```

To try it by hand on a real plan:

```bash
terraform show -json spacelift.plan > /tmp/infra-review.plan.json
ANTHROPIC_API_KEY=sk-ant-... TF_VAR_spacelift_run_type=PROPOSED \
  node agent.mjs /tmp/infra-review.plan.json
```

## PoC scope / next steps

Deliberately out of scope for now: posting PR comments (no VCS token inside
workers), retries/backoff, multi-turn tool use (e.g. an OpenTofu MCP server),
and a managed `agent policy` resource to schedule reviews at other run
stages. The context delivery + env config is designed so each of those is an
additive change.

### Hardening backlog

Known next-layer defenses, deferred on purpose:

* **Structural, byte-accurate truncation.** Truncation currently slices the
  serialized JSON string by JS string length, which can cut mid-token and
  miscounts multi-byte characters. Use `Buffer.byteLength` budgeting and cut
  on object boundaries so the model always receives valid JSON.
* **Review projection instead of the whole plan.** Send an allowlisted
  projection (addresses, actions, non-sensitive arguments) rather than the
  redacted full plan — smaller attack surface and smaller token spend, at the
  cost of building the projection schema.
* **Model-eval injection tests.** Repeated-run evals that plant prompt
  injections in plans/specs and assert the model ignores them (the current
  prompt-hardening is instruction-level, not eval-verified).
