#!/usr/bin/env bash
#
# Every `uses:` in .github/workflows must reference a full 40-character commit
# SHA (or be one of this repo's own path-local actions).
#
# This is the check that keeps the pinning invariant from decaying. Pinning by
# hand once is easy; staying pinned across a year of edits is not, and a single
# `uses: some/action@v4` reintroduces "whoever controls that tag controls a job
# in this repo" — in a repo whose tracked branch is executed by a stack holding
# Space-admin, that is a privilege-escalation path with extra steps.
#
# Blocking on purpose, and cheap: no network, no tools beyond grep and sed.

set -uo pipefail

cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

fail=0
seen=0

while IFS= read -r entry; do
  # Split on the first two colons only — action refs contain colons of their own
  # (docker://image:tag), so a naive field split corrupts them.
  file="${entry%%:*}"
  rest="${entry#*:}"
  line="${rest%%:*}"
  content="${rest#*:}"

  ref="$(printf '%s' "$content" |
    sed -E 's/^[[:space:]]*-?[[:space:]]*uses:[[:space:]]*//; s/[[:space:]]*#.*$//; s/^["'"'"']//; s/["'"'"']$//; s/[[:space:]]*$//')"

  seen=$((seen + 1))

  case "$ref" in
  ./* | .\\* )
    # This repo's own composite actions: reviewed through the same CODEOWNERS
    # path as everything else in .github/, so there is nothing to pin to.
    continue
    ;;
  docker://*)
    case "$ref" in
    *@sha256:*) continue ;;
    *)
      echo "$file:$line: '$ref' — container actions must be pinned by @sha256: digest, a registry tag is as mutable as a git tag" >&2
      fail=1
      continue
      ;;
    esac
    ;;
  esac

  pin="${ref##*@}"
  if [ "$pin" = "$ref" ] || ! printf '%s' "$pin" | grep -Eq '^[0-9a-f]{40}$'; then
    echo "$file:$line: '$ref' is not pinned to a full commit SHA" >&2
    fail=1
    continue
  fi

  # A bare SHA is unreviewable — nobody can tell v4 from an attacker's fork at a
  # glance — so the human-readable version has to sit beside it.
  if ! printf '%s' "$content" | grep -Eq '#[[:space:]]*v?[0-9]'; then
    echo "$file:$line: SHA pin needs a trailing '# vX.Y.Z' comment so reviewers can read it" >&2
    fail=1
  fi
done < <(grep -rnE '^[[:space:]]*-?[[:space:]]*uses:[[:space:]]*[^[:space:]]' \
  --include='*.yml' --include='*.yaml' .github/workflows 2>/dev/null)

if [ "$fail" -eq 0 ]; then
  echo "$seen workflow action reference(s), all SHA-pinned"
fi
exit "$fail"
