# Branch protection for `main`

Hardening-backlog item 1. **This cannot be configured from inside the repo** —
it is repository settings, not code — so it is written down here and an operator
with admin applies it once. Until they do, `CODEOWNERS` enforces nothing.

## Why this is not ordinary branch protection

The engine stacks (`iam-factory`, `nonadmin-launcher`, `app-factory`) are bound
to a tracked branch and hold **Space-admin**. Spacelift executes whatever is on
that branch. There is no step between *merged* and *running with elevated
credentials*.

So on this repo:

- an unreviewed merge is a privilege escalation, not a code-quality problem;
- a force-push that rewrites `main` rewrites what the elevated stack will run;
- an admin who bypasses the gate bypasses the only gate.

Everything below follows from that. Rules are ordered by what they stop.

---

## Apply in two stages — this repo has one maintainer today

`Jnesspace` is a GitHub **user**, not an organisation (verified via the API), and
this repo currently has a single maintainer. That changes what you can turn on
right now, because **the review rules need two humans to be a gate rather than a
deadlock**: GitHub never counts a self-approval, so "required approvals: 1" plus a
sole author means no PR can ever merge.

Do not let that stall the rest. Split it:

**Stage 1 — enable now, solo-safe, real enforcement.** Every one of these works
with one maintainer and closes most of the exposure:

```
Require a pull request                  on   (with required approvals: 0)
Required status checks                  on   (the four below)
Require branches to be up to date       on
Require conversation resolution         on
Require linear history                  on
Block force pushes                      on
Block deletions                         on
No bypass actors / enforce for admins   on
```

With approvals at 0 you still get: no direct pushes to `main`, no force-push
rewriting what the elevated stack already ran, no branch deletion, and **CI must
be green before merge**. That last one is the substantive gate today — it is
machine-enforced and needs no second person.

**Stage 2 — enable when a second maintainer exists.** These are the
separation-of-duties half, and they are the ones that actually close backlog
item 1:

```
Required approvals                      1  (2 once the team is 3+)
Require review from Code Owners         on
Dismiss stale approvals on push         on
Require approval of the most recent push on
```

Getting to Stage 2 means moving this repo into an organisation, creating a
platform team with write access, and swapping the handle in
[`CODEOWNERS`](CODEOWNERS) — a team handle cannot resolve in a user-owned repo,
and GitHub treats an unresolvable owner as *no owner*, so "Require review from
Code Owners" would silently pass. That fails open, which is worse than not
enabling it.

**Be honest about what Stage 1 leaves open:** the engine executes whatever lands
on `main` with Space-admin, and with approvals at 0 a single compromised or
careless maintainer account can still put code there. Stage 1 makes that
*auditable and CI-verified*; only Stage 2 makes it *reviewed*. Backlog item 1
stays open until then.

## The ruleset

The full target state (Stage 1 + Stage 2). The **Solo?** column says whether the
rule is safe to enable today with one maintainer.

| Rule | Setting | Solo? | Why, given a Space-admin stack runs this branch |
|---|---|---|---|
| Require a pull request | on | yes* | Direct pushes to `main` reach the engine with no review at all. This is the whole control. |
| Required approvals | **1** (2 once the team is 3+) | **no** | GitHub never counts a self-approval, so 1 already means "a second human looked". 2 is better and deadlocks a two-person team — pick the number you will not route around. |
| Require review from Code Owners | on | **no** | Without this, approvals count but `CODEOWNERS` is decoration: anyone with write can approve a change to `bootstrap/`. |
| Dismiss stale approvals on push | on | **no** | Otherwise the reviewed diff and the merged diff are different documents. Approve-then-append is the cheapest way to land unreviewed code on an elevated branch. |
| Require approval of the most recent push | on | **no** | Stops the author approving their own follow-up commits, and stops the approver being the last pusher. Complements backlog item 2 (no self-approval) on the Spacelift side. |
| Require conversation resolution | on | yes | A security question raised in review must be answered rather than scrolled past. |
| Required status checks | see below | yes | Review catches intent; CI catches breakage. Both, or the gate is half a gate. |
| Require branches to be up to date | on | yes | Two PRs that each pass alone can break `main` together. On this repo "broken `main`" means the engine's next run fails mid-provision. |
| Require linear history | on | yes | A merge commit hides which parent introduced a change. Post-incident, "what was on the branch when that run executed" must be answerable from `git log` alone. Requires squash/rebase-only merges — set that in repo settings too. |
| Block force pushes | on | yes | A force push retroactively changes what the elevated stack ran. It also breaks the audit trail that makes the rest of this repo defensible. |
| Block deletions | on | yes | Deleting `main` is a denial of service against every stack tracking it. |
| No bypass actors / enforce for admins | on | yes | The people most likely to hold admin are the people most likely to be phished. An exemption for admins is an exemption for whoever compromises one. |

\* Solo-safe **only with `required_approving_review_count: 0`**. The PR
requirement itself is what stops direct pushes to `main`; the approval count is
the part that needs a second human.

### Required status checks — exact names

Mark **only these four**:

```
terraform-gate
policy
security-gate
ci-hygiene
```

Each is a fixed-name gate job that fails unless its blocking upstream jobs
passed. **Do not mark the individual matrix jobs required.** `validate (…)` check
names are generated from wherever `.tf` files live, so the moment someone adds
`modules/oci/` there is a new check that nobody marked required — and a PR
touching only that directory would merge with it unverified. The gate job's name
does not change when the matrix does.

For the same reason, do not mark advisory checks required:

| Check | Blocking? | Why |
|---|---|---|
| `terraform-gate` | **yes** | `fmt` + `validate` over every root/module + `tflint`. All 45 directories are green today, so this blocks on real breakage only. |
| `policy` | **yes** | `opa fmt`, `opa check --strict`, `opa test`, plus package/directory structure. A policy in the wrong package attaches and enforces nothing. |
| `security-gate` | **yes** | Wraps `secret-scan` only (gitleaks, worktree + full history). A live credential in the tree is an incident, not a finding. |
| `ci-hygiene` | **yes** | `actionlint`, SHA-pin audit, `shellcheck`, `yamllint`. CI is privilege-bearing; it gets verified like the rest. |
| `iac-scan` | no | ~105 checkov/trivy findings on arrival, nearly all "this module does not enable \<production hardening\>" — correct for a production root, wrong for a wrapper module that also serves ephemeral demos. Blocking on that set teaches everyone to bypass, and the bypass habit then covers the findings that matter. |
| `secret-hygiene` | no | Hardcoded AWS account numbers and Spacelift entity ids. Real, and currently present in `.tf`/`.md` files — so a blocking check would be red the day it lands. Reported every run instead; promote it when the count hits zero. |
| `publish-sarif` | no | Pushes findings to the Security tab. Needs code scanning enabled on the repo; not a correctness signal. |

`integration_id: 15368` on each required check pins it to the GitHub Actions app,
so a third-party app cannot report a same-named green check.

---

## Apply it

Requires admin on the repo. `gh auth refresh -h github.com -s admin:org,repo`
first if the API returns 403.

```bash
OWNER=Jnesspace
REPO=platform-engineering
```

### Preferred: a repository ruleset

Rulesets are additive, versioned, and show which rule blocked a push. Classic
branch protection does not.

```bash
gh api -X POST "repos/$OWNER/$REPO/rulesets" --input - <<'JSON'
{
  "name": "main — elevated stack tracked branch",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "bypass_actors": [],
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "required_linear_history" },
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 1,
        "dismiss_stale_reviews_on_push": true,
        "require_code_owner_review": true,
        "require_last_push_approval": true,
        "required_review_thread_resolution": true,
        "allowed_merge_methods": ["squash", "rebase"]
      }
    },
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": true,
        "do_not_enforce_on_create": false,
        "required_status_checks": [
          { "context": "terraform-gate", "integration_id": 15368 },
          { "context": "policy",         "integration_id": 15368 },
          { "context": "security-gate",  "integration_id": 15368 },
          { "context": "ci-hygiene",     "integration_id": 15368 }
        ]
      }
    }
  ]
}
JSON
```

#### Stage 1 variant — apply this today

The JSON above is the target state and will deadlock merges while this repo has a
single maintainer. To apply now, send the same payload with the `pull_request`
rule's parameters replaced by:

```json
{
  "type": "pull_request",
  "parameters": {
    "required_approving_review_count": 0,
    "dismiss_stale_reviews_on_push": false,
    "require_code_owner_review": false,
    "require_last_push_approval": false,
    "required_review_thread_resolution": true,
    "allowed_merge_methods": ["squash", "rebase"]
  }
}
```

Everything else — `deletion`, `non_fast_forward`, `required_linear_history`,
`required_status_checks`, `"bypass_actors": []` — stays exactly as written. When a
second maintainer joins, `PUT` the ruleset back to the full version above; that is
the one-line change that closes backlog item 1.

`"bypass_actors": []` is the enforce-for-admins equivalent, and it is the line
most likely to be quietly edited later. Audit it:

```bash
gh api "repos/$OWNER/$REPO/rulesets" --jq '.[] | {id, name, enforcement}'
gh api "repos/$OWNER/$REPO/rulesets/RULESET_ID" --jq '.bypass_actors'   # must be []
```

### Alternative: classic branch protection

Use this if the org still standardises on classic protection. Same intent.

```bash
gh api -X PUT "repos/$OWNER/$REPO/branches/main/protection" --input - <<'JSON'
{
  "required_status_checks": {
    "strict": true,
    "checks": [
      { "context": "terraform-gate", "app_id": 15368 },
      { "context": "policy",         "app_id": 15368 },
      { "context": "security-gate",  "app_id": 15368 },
      { "context": "ci-hygiene",     "app_id": 15368 }
    ]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "required_approving_review_count": 1,
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": true,
    "require_last_push_approval": true,
    "bypass_pull_request_allowances": { "users": [], "teams": [], "apps": [] }
  },
  "required_linear_history": true,
  "required_conversation_resolution": true,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "block_creations": false,
  "lock_branch": false,
  "allow_fork_syncing": false,
  "restrictions": null
}
JSON
```

### Also protect `stage` and `dev`

`bootstrap/environments/` tracks `dev`, `stage`, and `main` — so all three are
branches an app-factory stack executes, and `dev` is the one people treat as
scratch. Apply the same ruleset with a lower approval bar rather than none:

```bash
# Same JSON as above with:
#   "conditions": { "ref_name": { "include": ["refs/heads/stage", "refs/heads/dev"], "exclude": [] } }
#   "name": "stage/dev — env-tracked branches"
```

---

## Repository settings that branch protection does not cover

Branch protection is necessary and not sufficient. Each of these is a way to
land code on `main`, or to run code in this repo's context, without touching the
branch rules.

```bash
# 1. Default GITHUB_TOKEN is read-only, and Actions cannot approve PRs.
#    Without the second flag, a workflow can satisfy the review requirement —
#    the review gate is then a gate a bot opens.
gh api -X PUT "repos/$OWNER/$REPO/actions/permissions/workflow" -f default_workflow_permissions=read \
  -F can_approve_pull_request_reviews=false

# 2. Squash/rebase only, so "require linear history" does not just fail merges.
gh api -X PATCH "repos/$OWNER/$REPO" \
  -F allow_merge_commit=false -F allow_squash_merge=true -F allow_rebase_merge=true \
  -F delete_branch_on_merge=true

# 3. Secret scanning + push protection. Rejects a credential at push time,
#    which is the only point where "rotate it" is still cheap. CI's gitleaks job
#    is the backstop, not the front line.
gh api -X PATCH "repos/$OWNER/$REPO" --input - <<'JSON'
{ "security_and_analysis": {
    "secret_scanning": { "status": "enabled" },
    "secret_scanning_push_protection": { "status": "enabled" } } }
JSON
```

**Settings → Actions → Fork pull request workflows: "Require approval for all
outside collaborators."** Not scriptable via a stable API. This matters here:
a fork PR runs the contributor's code on a runner. The workflows in this repo are
built so that is safe — `pull_request` not `pull_request_target`, no secrets,
read-only tokens — but the setting is the defence in depth for the day someone
adds a workflow that forgets one of those.

---

## What this does *not* protect

Branch protection covers the tracked branch. It does not cover **proposed runs**.

A PR against an engine stack triggers a proposed run, and a proposed run executes
plan-time Terraform — `data` sources, provisioners, `external` — against the
elevated engine, *before* any human approves the merge. That is hardening-backlog
item 3 and it is fixed on the Spacelift side, with a `GIT_PUSH` policy
(`policies/push/ignore-untrusted-authors.rego`). Neither half is sufficient
alone:

- branch protection without the push policy → an unmergeable PR still gets
  plan-time execution on the elevated engine;
- the push policy without branch protection → nothing stops a direct push to
  `main`, which skips proposed runs entirely and goes straight to apply.

Apply both.

## Verify

```bash
gh api "repos/$OWNER/$REPO/codeowners/errors" --jq '.errors'     # must be []
gh api "repos/$OWNER/$REPO/rulesets" --jq '.[].name'
gh api -X GET "repos/$OWNER/$REPO/actions/permissions/workflow"  # read + no PR approval
```

An empty `codeowners/errors` is the one to actually check: an unresolvable team
handle makes "require code owner review" pass with no owner, and it fails open.
