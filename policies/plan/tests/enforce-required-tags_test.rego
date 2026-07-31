package tests.plan.enforce_required_tags

import data.spacelift
import rego.v1

denials(fixture) := msgs if {
	msgs := spacelift.deny with input as fixture
}

matched(msgs, substring) if {
	some m in msgs
	contains(m, substring)
}

plan(changes) := {"terraform": {"resource_changes": changes}}

complete := {"Environment": "dev", "Project": "jimmy", "Owner": "platform"}

test_denies_untagged_aws_resource if {
	msgs := denials(plan([{
		"address": "aws_s3_bucket.data",
		"type": "aws_s3_bucket",
		"change": {"actions": ["create"], "after": {"bucket": "data", "tags_all": {"Environment": "dev"}}},
	}]))

	matched(msgs, "aws_s3_bucket.data is missing required tags: owner, project")
}

test_allows_fully_tagged_aws_resource if {
	msgs := denials(plan([{
		"address": "aws_s3_bucket.data",
		"type": "aws_s3_bucket",
		"change": {"actions": ["create"], "after": {"bucket": "data", "tags_all": complete}},
	}]))

	not matched(msgs, "missing required tags")
}

# tags_all is AWS-only; Azure resources carry `tags` and GCP `labels`, which the original
# tags_all-only check never looked at.
test_reads_azure_tags if {
	msgs := denials(plan([{
		"address": "azurerm_storage_account.data",
		"type": "azurerm_storage_account",
		"change": {"actions": ["create"], "after": {"tags": {"Environment": "dev"}}},
	}]))

	matched(msgs, "azurerm_storage_account.data is missing required tags: owner, project")
}

test_reads_gcp_labels if {
	msgs := denials(plan([{
		"address": "google_storage_bucket.data",
		"type": "google_storage_bucket",
		"change": {"actions": ["create"], "after": {"labels": complete}},
	}]))

	not matched(msgs, "missing required tags")
}

# GCP label keys are lowercase-only, so the required set is matched case-insensitively: lowercase
# labels must satisfy the policy exactly as title-case AWS/Azure tags do.
test_allows_lowercase_gcp_labels if {
	msgs := denials(plan([{
		"address": "google_storage_bucket.data",
		"type": "google_storage_bucket",
		"change": {"actions": ["create"], "after": {"labels": {
			"environment": "dev",
			"project": "jimmy",
			"owner": "platform",
		}}},
	}]))

	not matched(msgs, "missing required tags")
}

# AWS resources expose tags and tags_all together; the union must not abort the evaluation.
test_handles_both_tags_and_tags_all if {
	msgs := denials(plan([{
		"address": "aws_s3_bucket.data",
		"type": "aws_s3_bucket",
		"change": {"actions": ["create"], "after": {
			"tags": {"Environment": "dev", "Project": "jimmy"},
			"tags_all": complete,
		}},
	}]))

	not matched(msgs, "missing required tags")
}

# Only false and undefined are falsy in Rego, so `not tags[t]` would have accepted a null tag.
test_denies_null_tag_value if {
	msgs := denials(plan([{
		"address": "aws_s3_bucket.data",
		"type": "aws_s3_bucket",
		"change": {"actions": ["create"], "after": {"tags_all": {
			"Environment": null,
			"Project": "jimmy",
			"Owner": "platform",
		}}},
	}]))

	matched(msgs, "missing required tags: environment")
}

test_denies_empty_tag_value if {
	msgs := denials(plan([{
		"address": "aws_s3_bucket.data",
		"type": "aws_s3_bucket",
		"change": {"actions": ["create"], "after": {"tags_all": {
			"Environment": "",
			"Project": "jimmy",
			"Owner": "platform",
		}}},
	}]))

	matched(msgs, "missing required tags: environment")
}

# Resources with no tag attribute at all are deliberately out of scope.
test_skips_untaggable_resources if {
	msgs := denials(plan([{
		"address": "spacelift_space.team",
		"type": "spacelift_space",
		"change": {"actions": ["create"], "after": {"name": "team", "labels": ["shared"]}},
	}]))

	not matched(msgs, "missing required tags")
	not matched(
		warnings(plan([{
			"address": "spacelift_space.team",
			"type": "spacelift_space",
			"change": {"actions": ["create"], "after": {"name": "team", "labels": ["shared"]}},
		}])),
		"unknown at plan time",
	)
}

test_skips_deletes if {
	msgs := denials(plan([{
		"address": "aws_s3_bucket.data",
		"type": "aws_s3_bucket",
		"change": {"actions": ["delete"], "before": {"tags_all": {}}},
	}]))

	not matched(msgs, "missing required tags")
}

warnings(fixture) := msgs if {
	msgs := spacelift.warn with input as fixture
}

# Terraform omits unknown values from `after`, so a taggable resource whose tags are computed
# produces no tag object at all — the deny cannot see it, so the warn has to.
test_warns_when_tags_are_unknown_at_plan_time if {
	msgs := warnings(plan([{
		"address": "aws_s3_bucket.data",
		"type": "aws_s3_bucket",
		"change": {"actions": ["create"], "after": {"bucket": "data"}},
	}]))

	matched(msgs, "aws_s3_bucket.data has no tags in the plan")
}
