#!/usr/bin/env bash
# opa test with per-policy isolation — and the 1:1 test-pairing gate.
#
# Spacelift evaluates each policy in isolation, but `opa test policies/` merges every file into
# one package spacelift. For positive rules (approve) that union is unfaithful to production:
# a weaker sibling body (e.g. `approve if not requires_review` without no_rejections) silently
# satisfies the stricter file's tests. Running each policy with ONLY its own test file matches
# what Spacelift actually evaluates — and a policy without a matching test file fails here,
# which is what keeps the next policy from landing untested.
#
# The push/ directory is the deliberate exception: its three policies compose by design
# ("Spacelift ignores a push if ANY attached policy says ignore"), and their tests assert on
# the merged result — so push runs as a family, mirroring that composition.
set -euo pipefail
cd "$(dirname "$0")/../.."

fail=0
count=0

while IFS= read -r policy; do
  dir="$(dirname "$policy")"
  name="$(basename "$policy" .rego)"
  test_file="${dir}/tests/${name}_test.rego"

  if [ ! -f "$test_file" ]; then
    echo "::error file=${policy}::missing test file ${test_file}"
    fail=1
    continue
  fi

  count=$((count + 1))
  echo "--- ${policy} (isolated)"
  opa test "$policy" "$test_file" || fail=1
done < <(find policies -name '*.rego' -not -path '*/tests/*' -not -path 'policies/push/*' | sort)

echo "--- policies/push/ (family run: the three policies compose by design)"
opa test policies/push/ || fail=1

echo "per-policy isolation: ${count} policies tested, plus the push family"
exit "$fail"
