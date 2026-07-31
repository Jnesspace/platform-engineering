# PLAN: deny resources created or updated without the required tags. Checks every tag attribute the repo's providers use — tags_all is AWS-only, and modules/ also covers Azure (tags) and GCP (labels).
package spacelift

import rego.v1

# Matched case-insensitively: the AWS/Azure convention is title-case (Environment), but GCP
# label keys are lowercase-only (environment), and GCP modules pass var.labels straight through.
# Either casing proves the tag exists; requiring one spelling made compliant GCP resources
# undeliverable and compliant AWS/Azure resources non-portable.
required_tags := {"environment", "project", "owner"}

tag_attributes := ["tags_all", "tags", "labels"]

# Managed types under these providers are taggable; everything else in the repo (spacelift_*,
# random_*, time_*, terraform_data) legitimately carries no tags and stays out of scope.
taggable_provider_prefixes := {"aws_", "azurerm_", "google_"}

# Union rather than first-match: AWS resources expose both `tags` and `tags_all`, and a
# function that produced one output per attribute would abort the evaluation.
tag_union(resource) := object.union_n(maps) if {
	maps := [m |
		some attribute in tag_attributes
		m := resource.change.after[attribute]
		is_object(m)
	]
	count(maps) > 0
}

# An explicit null or empty value is not a tag. `not m[key]` would accept both, since only
# false and undefined are falsy in Rego.
has_tag(m, key) if {
	some k, v in m
	lower(k) == key
	is_string(v)
	v != ""
}

taggable(resource) if {
	some prefix in taggable_provider_prefixes
	startswith(resource.type, prefix)
}

tag_object_present(resource) if {
	some attribute in tag_attributes
	is_object(object.get(resource.change, ["after", attribute], null))
}

deny contains msg if {
	some r in input.terraform.resource_changes
	some action in r.change.actions
	action in {"create", "update"}

	# Resources with no tag attribute at all (spacelift_*, terraform_data) are skipped.
	m := tag_union(r)
	missing := {t | some t in required_tags; not has_tag(m, t)}
	count(missing) > 0

	msg := sprintf("%s is missing required tags: %s", [r.address, concat(", ", sort(missing))])
}

# Terraform omits unknown values from `after`, so a resource whose tags are computed — merged
# from a context variable, or an unresolved provider default_tags — yields no tag object and
# the deny above never fires. Warn, matching protect-env-labels' unknown-labels handling,
# rather than let an untagged resource slip through on a technicality.
warn contains msg if {
	some r in input.terraform.resource_changes
	some action in r.change.actions
	action in {"create", "update"}
	taggable(r)
	not tag_object_present(r)

	msg := sprintf("%s has no tags in the plan (unknown at plan time); confirm Environment/Project/Owner are set", [r.address])
}

sample := true
