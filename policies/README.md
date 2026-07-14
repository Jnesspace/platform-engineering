# Spacelift Policy Library

Standalone, attachable Spacelift policies (`package spacelift`, Rego v1): grab a file, adjust the constants at the top, attach.

| file | type | enforces |
| --- | --- | --- |
| plan/enforce-required-tags.rego | PLAN | Deny resources created/updated without required tags |
| plan/deny-privileged-iam.rego | PLAN | Deny creation of spacelift_role, spacelift_role_attachment, and IAM users/keys |
| plan/cap-new-resources.rego | PLAN | Deny plans creating more than N resources at once |
| plan/protect-env-labels.rego | PLAN | Deny env:* label changes on spacelift_stack resources |
| approval/deny-self-approval.rego | APPROVAL | Require an approval from someone other than the run's triggerer |
| approval/require-prod-approval.rego | APPROVAL | Two approvals for env:prod stacks; auto-approve elsewhere |
| push/ignore-untrusted-authors.rego | GIT_PUSH | Ignore PRs from untrusted authors and forks; propose only trusted same-repo PRs |
| push/track-intended-changes.rego | GIT_PUSH | Track only the stack's branch/project root; propose PRs targeting that branch |
| login/map-idp-groups.rego | LOGIN | Map IdP groups to roles: platform team is admin, app teams get Space Admin on their spaces |
| access/team-space-access.rego | ACCESS | Write for a stack's owning team (team:* label), read for org-visible stacks |
| trigger/trigger-dependencies.rego | TRIGGER | Trigger stacks labeled depends-on:\<id\> after a successful tracked run |
| notification/notify-failed-runs.rego | NOTIFICATION | Route failed non-proposed runs to a Slack channel |

The PLAN, APPROVAL, and GIT_PUSH policies implement the plan-guardrail, approval, and safe-proposed-run items from the hardening backlog.
