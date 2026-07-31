# Cross-file consistency: six constants across five files each answer "which labels mark a stack
# as privileged", and they can only be compared here — Spacelift evaluates each policy in
# isolation, so the sets are duplicated by necessity and this merged test is what keeps the
# duplicates from drifting apart (proposed-run-safety once missed poc:nonadmin-launcher, leaving
# the launcher's own stacks without proposed-run withholding).
package tests.plan.privileged_label_consistency

import data.spacelift
import rego.v1

# The proposed-run gate must cover every label that gates a plan guardrail: any stack whose runs
# get an elevated token is precisely a stack that must not plan PR-authored code unreviewed.
test_elevated_covers_launcher_labels if {
	missing := spacelift.launcher_stack_labels - spacelift.elevated_labels
	missing == set()
}

test_elevated_covers_factory_labels if {
	missing := spacelift.factory_stack_labels - spacelift.elevated_labels
	missing == set()
}

test_elevated_covers_trust_boundary_labels if {
	missing := spacelift.trust_stack_labels - spacelift.elevated_labels
	missing == set()
}

# The labels that REVOKE the bootstrap exemption in deny-privileged-iam are engine labels by
# definition; every one of them must also withhold unreviewed proposed runs.
test_elevated_covers_disqualifying_labels if {
	missing := spacelift.bootstrap_disqualifying_labels - spacelift.elevated_labels
	missing == set()
}

# The document-inspection exemption in deny-privileged-iam must name exactly the stacks the
# trust-boundary policy inspects — no more (a wider set would exempt uninspected stacks), no
# less (the factory would be double-reported).
test_document_exemption_matches_trust_boundary if {
	spacelift.document_inspection_exempt_labels == spacelift.trust_stack_labels
}

# protect-env-labels treats guardrail-gating labels as protected; it must cover every label the
# launcher forbids a vended stack from claiming, or a vended stack could be relabelled into a
# privilege claim post-create.
test_protected_labels_cover_launcher_forbidden if {
	missing := (spacelift.launcher_forbidden_labels - spacelift.guardrail_labels) - {"env:prod"}
	missing == set()
}
