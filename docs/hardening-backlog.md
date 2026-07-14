# Hardening backlog

**This repo is a PoC. It is NOT yet production-safe.** The patterns prove the
privilege model (stack-bound elevation, catalog-gated roles); the controls
below were deliberately deferred and are required before real teams and real
credentials touch this. Each item comes from the security review of the live
PoC.

1. **Protect the tracked git branch (branch protection + CODEOWNERS).**
   The engine executes whatever is on its tracked branch with elevated
   credentials; keeping this repo separate from team-writable repos is the
   first mitigation, but branch protection is still required.

2. **APPROVAL policy denying self-approval + split requester/approver roles.**
   Today `RUN_TRIGGER` + `RUN_CONFIRM` live in one consumer role, so the
   confirm gate is self-approvable by the same person who triggered the run.

3. **GIT_PUSH policy to make proposed runs safe.**
   Proposed runs from PRs execute plan-time code — an unreviewed PR is a
   plan-time RCE risk against the elevated engine.

4. **PLAN policy guardrail on the engine.**
   Pin the target space, cap the stack count, deny role/attachment creation,
   and constrain names/labels — so even a compromised or buggy engine run
   cannot exceed its intended shape.

5. **Dedicated private worker pool for the elevated engine.**
   Don't run the elevated token on shared workers, where co-tenant runs widen
   the theft surface.

6. **Apply the same guardrails to iam-factory.**
   It has the bigger blast radius (platform-admin scope over Space and IAM
   vending), so items 1-5 apply there at least as strongly.
