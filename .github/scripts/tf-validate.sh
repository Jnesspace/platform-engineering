#!/usr/bin/env bash
#
# terraform init -backend=false + terraform validate over the given directories
# (default: everything tf-discover.sh finds).
#
# Shared by CI and .pre-commit-config.yaml on purpose — a local check that is
# only *nearly* the same as the CI check teaches contributors to distrust both.
#
# No credentials are used or needed, and that must stay true:
#   -backend=false  never contacts remote state
#   validate        is a type/reference check; it calls no provider API
# Nothing here can be turned into an apply by editing an argument.

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

# One shared provider cache across every directory in the run. Without it the
# aws module tree downloads the same 400MB provider eight times. Safe with the
# committed lock files because they carry the registry's platform-independent
# zh: hashes, so Terraform can verify a cached package on any OS and simply
# records the local h1: hash it was missing.
: "${TF_PLUGIN_CACHE_DIR:=${HOME}/.terraform.d/plugin-cache}"
export TF_PLUGIN_CACHE_DIR TF_IN_AUTOMATION=1 TF_INPUT=0
mkdir -p "$TF_PLUGIN_CACHE_DIR"

TF="${TERRAFORM_BIN:-terraform}"

if [ $# -gt 0 ]; then
  dirs=("$@")
else
  # shellcheck disable=SC2207
  dirs=($("$here/tf-discover.sh" --list))
fi

# bash 3.2 (still what macOS ships) errors on "${empty[@]}" under set -u, and an
# empty list means discovery broke rather than "nothing to check".
if [ ${#dirs[@]} -eq 0 ]; then
  echo "no Terraform directories to validate — discovery is broken" >&2
  exit 1
fi

failed=()
for d in "${dirs[@]}"; do
  [ -d "$d" ] || { echo "skip (gone): $d"; continue; }
  printf '\n==> %s\n' "$d"
  # -lockfile=readonly: init may never rewrite a committed lock file — a provider-constraint
  # change must arrive WITH its lock update, or the run that later applies it drifts from what
  # CI validated. Every discovered root has a committed lock, so this costs nothing.
  if ! ( cd "$d" && "$TF" init -backend=false -input=false -lockfile=readonly -no-color >/dev/null \
                 && "$TF" validate -no-color ); then
    failed+=("$d")
  fi
done

printf '\n%s\n' "----------------------------------------"
printf 'validated %d directories, %d failed\n' "${#dirs[@]}" "${#failed[@]}"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    if [ ${#failed[@]} -eq 0 ]; then
      printf '%d Terraform directories validated clean.\n\n' "${#dirs[@]}"
    else
      printf '### terraform validate failures (%d/%d)\n\n' "${#failed[@]}" "${#dirs[@]}"
      # shellcheck disable=SC2016  # the backticks are markdown, not a subshell
      printf -- '- `%s`\n' "${failed[@]}"
      printf '\n'
    fi
  } >>"$GITHUB_STEP_SUMMARY"
fi

[ ${#failed[@]} -eq 0 ] || { printf 'failed:\n'; printf '  %s\n' "${failed[@]}"; exit 1; }
