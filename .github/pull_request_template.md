# What and why

<!-- One or two sentences. The diff shows what changed; say why it needed to. -->

## Privilege check

The engine stacks execute this repo's tracked branch holding **Space-admin**.
Merging is the last gate. Answer these — "no" to all four is a normal PR.

- [ ] **Touches privilege.** Changes anything under `bootstrap/`, `roles/`, or
      `worker-pools/` — i.e. creates, binds, or relocates elevation.
- [ ] **Touches an elevated stack's code.** Changes `patterns/` or `schedules/` —
      code that runs *with* those credentials, on a trigger or a timer.
- [ ] **Touches policy.** Changes `policies/`. A weakened Rego rule is
      indistinguishable from a deleted gate and does not look privileged in a diff.
- [ ] **Touches CI.** Changes `.github/` or a scanner config (`.tflint.hcl`,
      `.checkov.yaml`, `.gitleaks.toml`, `.yamllint.yaml`, `.gitignore`). Whoever
      can edit a workflow can run code in this repo's context.

If any box is ticked, say here **what new thing becomes possible after this
merges that was not possible before** — for a person, for a stack, or for a
workflow:

<!-- e.g. "the app-factory stack can now create IAM roles in the shared account,
     where before it could only read them" -->

## Blast radius

- [ ] No new privilege is granted, and no existing scope is widened.
- [ ] No credential, account id, or Spacelift entity id is hardcoded — including
      in a variable `default` and in docs. (`secret-hygiene` in CI reports these;
      it is advisory, so read it rather than trusting the green check.)
- [ ] Terraform module changes are backwards compatible for existing callers, or
      the breaking change is called out above.

## Verification

- [ ] CI is green. State plainly if a check is red and why it is acceptable —
      a red check waved through once becomes a red check ignored forever.
- [ ] Ran locally: `pre-commit run --all-files`, and for Terraform changes
      `pre-commit run --all-files --hook-stage pre-push` (that is where
      `terraform validate` and `tflint` live — they need the network).
- [ ] For `policies/`: added or updated `*_test.rego`. An untested policy is an
      unproven gate, and `opa test` passes vacuously on an empty test set.

<!-- Reviewers: CODEOWNERS on a privilege-bearing path means the review *is* the
     privilege boundary, not a second opinion. See .github/BRANCH_PROTECTION.md. -->
