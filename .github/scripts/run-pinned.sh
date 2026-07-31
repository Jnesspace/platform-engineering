#!/usr/bin/env bash
#
# Run a pinned tool, installing it on first use. One entry point so a workflow
# step and a pre-commit hook invoke the byte-identical binary.
#
# Usage: run-pinned.sh <gitleaks|actionlint> [args...]

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tool="${1:?usage: $0 <gitleaks|actionlint> [args...]}"
shift

exec "$("$here/install-pinned.sh" "$tool")" "$@"
