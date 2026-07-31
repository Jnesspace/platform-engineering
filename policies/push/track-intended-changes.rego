# GIT_PUSH: scope each stack to its own project root so one repo can host many stacks. Mirrors Spacelift's documented default policy — the hand-rolled version ignored PR diffs and broke outright on stacks with no project root.
package spacelift

import rego.v1

# project_root is optional in the input; absent means the repo root, which every path
# matches. Building a "root/" prefix from an absent value ignores every push instead.
default project_prefix := ""

project_prefix := trim(root, "/") if {
	root := object.get(input, ["stack", "project_root"], "")
	is_string(root)
}

# An empty prefix (repo root) matches everything. Otherwise match the root exactly or with a
# trailing slash — a bare startswith would let root `foo` swallow the sibling `foobar/`.
in_project(_) if project_prefix == ""

in_project(path) if trim(path, "/") == project_prefix

in_project(path) if {
	project_prefix != ""
	startswith(trim(path, "/"), sprintf("%s/", [project_prefix]))
}

in_project(path) if {
	some pattern in input.stack.additional_project_globs
	glob.match(pattern, ["/"], trim(path, "/"))
}

# Push events carry every file from every commit in the push...
affected if {
	some path in input.push.affected_files
	in_project(path)
}

# ...while a PR must be judged on the whole diff. `push` on a PR event is only the head
# commit, so a relevant change in an earlier commit would look like an unrelated PR.
affected_pr if {
	some path in input.pull_request.diff
	in_project(path)
}

track if {
	affected
	input.push.branch == input.stack.branch
}

# Deliberately tighter than the Spacelift default: only PRs aimed at the tracked branch
# get a proposed run, never a bare push to some feature branch.
propose if {
	affected_pr
	input.pull_request.base.branch == input.stack.branch
}

ignore if {
	not affected
	not affected_pr
}

# Tags drive module releases, not stack runs.
ignore if input.push.tag != ""

sample := true
