# Hardening backlog

**This repo is a PoC.** The patterns prove the privilege model (stack-bound
elevation, catalog-gated roles). The controls below were deliberately deferred
in the original build; most are now implemented, and what remains is stated
plainly rather than quietly closed.

Two things are true at once, and both matter:

- The **code-side** controls are in place and verified — policies published and
  attached, elevated stacks on a private pool, self-approval broken structurally.
- Nothing here is enforced until an operator **applies** the new roots and sets
  GitHub branch protection. Until then this is a repo that *describes* its
  guardrails.

## Status of the original seven

| # | Item | Status |
|---|---|---|
| 1 | Branch protection + CODEOWNERS | **Open** — written, not applied; separation of duties is blocked on the repo being user-owned |
| 2 | APPROVAL policy + requester/approver split | **Closed** (code) |
| 3 | GIT_PUSH policy for proposed runs | **Closed** (code) |
| 4 | PLAN guardrail on the launcher engine | **Closed** (code) |
| 5 | Private worker pool for elevated stacks | **Closed** (code) |
| 6 | Same guardrails on iam-factory | **Closed** (code) |
| 7 | Vended-Space inheritance (`inherit_entities = false`) | **Open** — structural, see below |

### What "closed" rests on

The whole policy layer previously existed as `.rego` files that **nothing
attached to any stack** — twelve guardrails that could never fire. That is now
delivered by [`bootstrap/governance/`](../bootstrap/governance), which discovers
`policies/<type>/*.rego` and auto-attaches by label, and fails its own plan if an
`elevated` stack lacks a private worker pool, deletion protection, or policy
reach. Adding a `.rego` file to the right directory is all it takes to deploy it.

The policies themselves were also audited against Spacelift's real input schemas,
because several had never been executed. Three were inert or inverted in ways
that mattered: `deny-self-approval` compared against a field that is null for
push-created runs, so **any single approval — including the author's own —
approved the run**; `track-intended-changes` could permanently ignore every push,
meaning the stack would never run at all; and `map-idp-groups` denied every
machine session, which would have broken the engines' own API access. There are
now 173 passing Rego unit tests, and each rule was mutation-tested (break it,
confirm a test fails) so a guardrail that silently never fires gets caught.

## Still open

### 1. Branch protection + CODEOWNERS

`.github/CODEOWNERS` exists and resolves. `.github/BRANCH_PROTECTION.md` has the
ruleset, the exact required status-check names, and ready-to-send API calls.

**Two things block full closure, and only one is in your control:**

- **It has to be applied by a human with repo admin.** Branch protection is
  repository settings, not code. Apply the **Stage 1** ruleset today — required
  status checks, no force-push, no deletion, linear history, no bypass actors.
  That is real, machine-enforced protection and needs no second person.
- **Separation of duties needs two humans and an organisation.** `Jnesspace` is
  a GitHub *user*, not an org, so team handles cannot resolve — and GitHub treats
  an unresolvable code owner as *no owner*, which makes "Require review from Code
  Owners" silently pass. Worse than not enabling it. A sole maintainer also
  cannot approve their own PR, so requiring approvals today deadlocks every
  merge instead of gating it.

**The fix:** move this repo into a GitHub organisation, create a platform team
with write access, swap the handle in `CODEOWNERS`, then enable Stage 2. Until
then the review gate — the only thing standing between "merged" and "executed
with Space-admin" — is not in place.

### 7. Vended-Space inheritance

Vended Spaces are created with `inherit_entities = true`. Tightening it is
**root-admin-only**, and the factory deliberately runs with Space-admin, so the
factory cannot do it — which is itself a proof of the anti-escalation boundary
working.

It cannot simply move to the bootstrap layer either. Bootstrap does not own the
vended Spaces (the factory creates them), so importing them starts a permanent
drift war where each root's next apply flips the flag back.

And `false` is not a free win. Inheritance is the transport for **governance**,
not just credentials — setting it would cut vended stacks off from the AWS
integration, the private worker pool, *and* the entire policy set, trading a
credential blast radius for a worse governance one.

**Root cause:** `root` holds both credentials and governance, so no single
inheritance value is correct for both. The concrete fix is documented in
[`bootstrap/iam-factory/README.md`](../bootstrap/iam-factory/README.md); step one
is provisioning the AWS integration in `platform-admin` rather than `root`, which
happens out-of-band, outside this repo.

## Found during the hardening pass

New, and not in the original seven.

| Item | Why it matters |
|---|---|
| **Apply the new roots in order** | `worker-pools/` → the three `bootstrap/*` roots → `bootstrap/governance/` → `roles/`. Account-specific values are now required variables with no defaults; see each root's `terraform.tfvars.example`. |
| **Burn down the advisory scanner findings** | CI runs checkov and `trivy config` as **advisory** (~105 findings, mostly "module does not enable \<production hardening\>"). Blocking on a set nobody can clear teaches people to bypass. Triage, then promote. |
| **Promote `secret-hygiene` to blocking** | It reports account identifiers still committed. Once the count is zero, make it a required check so it cannot regress. |
| **azurerm is pinned to legacy 3.x** | `>= 3.116.0, < 4.0.0`. The 4.x migration (mandatory `subscription_id`, `storage_account_id` on containers, several renames) is a repo-wide decision, not per-module. |
| **iam-factory vends one read+write role per Space** | `var.trust_scopes` makes splitting into read and write roles a one-line change per role, but vending the twin doubles every resource and rewires the auto-attached context. A design decision, not a hardening. |
| **Catalog sets still grant `Resource = "*"`** | The mechanism for per-set resource scoping exists (`catalog.yaml` accepts `{ actions, resources }`), but the shipped sets were not narrowed — changing live grants is an environment decision. |
| **Region lock is off by default** | `var.allowed_regions` adds an `aws:RequestedRegion` condition, left off because global-endpoint services (S3 `ListAllMyBuckets`, STS, IAM) report `us-east-1` and a careless lock breaks them in a way that looks like a permissions bug. |
| **`app-deploy` uses the worker's kubeconfig** | A bare `provider "kubernetes" {}`. Fine for the pattern, but it means the private worker pool is where that cluster credential actually lands. |
| **No cost governance on the shopping list** | Sizing fields (`instance_class`, `allocated_storage_gb`, `instance_type`) are deliberately *not* team-settable, so a `db.r5.24xlarge` from a YAML file is impossible today — but that also means teams cannot size anything. Doing it properly wants an operator allow-list plus a spend cap alongside `cap-new-resources`. |
| **There is no Azure or GCP app-factory** | `patterns/app-factory` is AWS-only by design (one root per cloud, because Terraform eagerly configures every declared provider). The Azure/GCP modules and their CMK variables are therefore unreachable from any engine — not a wiring gap, but the engines have to be built before those clouds are self-service. |
| **ACCESS, TASK and INITIALIZATION policies are retired** | Spacelift disabled creating them on 2026-05-30. `policies/access/team-space-access.rego` is kept as the record; `bootstrap/governance` refuses to publish retired types. The live equivalent is the `roles` rule in the LOGIN policy. |
