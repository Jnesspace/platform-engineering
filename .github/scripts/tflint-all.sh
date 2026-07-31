#!/usr/bin/env bash
#
# tflint over every discovered Terraform directory. Shared by CI and pre-commit.
#
# Per-directory --chdir rather than --recursive: --recursive walks the filesystem
# and would descend into gitignored provider trees, while tf-discover.sh reads the
# git index — the same set of directories the validate matrix covers, no more.
#
# Severity threshold is `warning`: errors and warnings fail, notices are printed.
# A notice ("that instance size is retiring") is information a reviewer wants and
# not a reason to block a merge.
#
# Deep checking — the tflint mode that calls the cloud APIs to resolve real
# resources — is off by default and must stay off. This repo has no credentials
# and that is a property worth keeping.

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

TFLINT="${TFLINT_BIN:-tflint}"
config="$PWD/.tflint.hcl"

if [ ! -d "${TFLINT_PLUGIN_DIR:-$HOME/.tflint.d/plugins}" ]; then
  "$TFLINT" --init --config="$config"
fi

rc=0
for d in $("$here/tf-discover.sh" --list); do
  "$TFLINT" --chdir="$d" --config="$config" --format=compact \
    --minimum-failure-severity=warning || rc=1
done

exit "$rc"
