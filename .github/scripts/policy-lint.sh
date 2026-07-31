#!/usr/bin/env bash
#
# Structural checks on policies/ that `opa check` cannot make, because they are
# about how Spacelift loads a policy rather than whether the Rego compiles.
#
# Both failure modes below produce a policy that compiles, attaches, and does
# nothing — the worst outcome for a control, since the gate looks present.
#
#   1. Wrong package. Spacelift evaluates `data.spacelift.<rule>`; a policy in
#      any other package is silently inert.
#   2. Wrong directory. The directory name is how a reader (and the attachment
#      code) knows a file's policy type, so it has to be a real Spacelift type.

set -uo pipefail

cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

# Spacelift's policy types, lowercased. GIT_PUSH's directory is `push` to match
# the existing tree. Adding a type here is the whole "support a new policy type"
# procedure.
VALID_TYPES=" access approval initialization login notification plan push task trigger "

fail=0
note() { printf '%s\n' "$1" >&2; fail=1; }

# No mapfile / readarray: macOS still ships bash 3.2 and this script runs from
# .pre-commit-config.yaml on developer laptops as well as in CI.
rego="$(git ls-files -- 'policies/*.rego' 2>/dev/null)"

if [ -z "$rego" ]; then
  note "no .rego files found under policies/ — discovery is broken or the tree moved"
  exit 1
fi

total=0
tests=0
for f in $rego; do
  total=$((total + 1))
  case "$f" in
  *_test.rego)
    tests=$((tests + 1))
    continue # tests may live in whatever package they like
    ;;
  esac

  if ! grep -Eq '^package[[:space:]]+spacelift[[:space:]]*$' "$f"; then
    note "$f: must declare 'package spacelift' — Spacelift evaluates data.spacelift.*, so any other package is inert"
  fi

  type_dir="$(printf '%s\n' "$f" | cut -d/ -f2)"
  if [ "$type_dir" = "$(basename "$f")" ]; then
    note "$f: policies live in policies/<type>/, not at the top of policies/"
  elif [[ "$VALID_TYPES" != *" $type_dir "* ]]; then
    note "$f: 'policies/$type_dir/' is not a Spacelift policy type (expected one of:$VALID_TYPES)"
  fi
done

# A policy library with no unit tests is a library nobody has proven. Not fatal
# yet — the tests are being written — but it must never be invisible, because
# `opa test` on a directory with zero test files exits 0 and looks like a pass.
policies=$((total - tests))
if [ "$tests" -eq 0 ]; then
  printf '::warning title=No policy tests::%s policies under policies/, 0 *_test.rego files. opa test exits 0 on an empty test set, so the policy gate is currently vacuous.\n' "$policies"
else
  printf 'policies: %s, test files: %s\n' "$policies" "$tests"
fi

exit "$fail"
