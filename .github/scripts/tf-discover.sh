#!/usr/bin/env bash
#
# Discover every directory Terraform must be able to init + validate, and shard
# them into matrix groups.
#
# Discovery is by *structure*, never by list. Several people add Terraform roots
# to this repo, and a hardcoded matrix rots silently: the new root simply stops
# being verified. In a repo whose tracked branch is executed by a Space-admin
# stack, "silently unverified" is the worst possible failure mode — so anything
# tracked in git with a .tf file in it is in scope, automatically.
#
# Usage:
#   tf-discover.sh --list              # one directory per line
#   tf-discover.sh --matrix            # JSON: [{"group":"modules/aws","dirs":"a b"}]
#   tf-discover.sh --groups            # one group name per line
#   tf-discover.sh --group modules/aws # directories in one group, space separated
#
# MAX_PER_GROUP (default 8) bounds job fan-out: a top-level directory with more
# members than that is split one level deeper. That keeps each job's provider
# download set small (the aws/azure/gcp module trees do not share providers)
# without ever needing a human to rebalance the matrix.

set -euo pipefail

MAX_PER_GROUP="${MAX_PER_GROUP:-8}"

cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

# git ls-files rather than find: it already honours .gitignore, so vendored
# .terraform/ provider trees and local cartogopher bakes/ can never reach the
# matrix, and it reads the index, so pre-commit sees staged-but-uncommitted
# roots too.
list_dirs() {
  local files
  files="$(git ls-files -- '*.tf' 2>/dev/null || true)"
  [ -n "$files" ] || return 0
  printf '%s\n' "$files" |
    awk 'BEGIN{FS="/"} { if (NF==1) print "."; else { sub(/\/[^\/]*$/, ""); print } }' |
    grep -v -e '^\.terraform$' -e '^\.terraform/' -e '/\.terraform/' |
    sort -u
}

# group<TAB>dir
pairs() {
  list_dirs | awk -v max="$MAX_PER_GROUP" '
    { dir[NR] = $0
      n = split($0, p, "/")
      one[NR] = p[1]
      two[NR] = (n >= 2) ? p[1] "/" p[2] : p[1]
      count[p[1]]++
    }
    END { for (i = 1; i <= NR; i++)
            print (count[one[i]] > max ? two[i] : one[i]) "\t" dir[i] }
  ' | sort
}

case "${1:---list}" in
--list)
  list_dirs
  ;;
--groups)
  pairs | cut -f1 | sort -u
  ;;
--group)
  [ $# -eq 2 ] || { echo "usage: $0 --group <name>" >&2; exit 2; }
  pairs | awk -F'\t' -v g="$2" '$1 == g { printf "%s ", $2 } END { print "" }'
  ;;
--matrix)
  pairs | jq -R -s -c '
    split("\n") | map(select(length > 0) | split("\t") | {group: .[0], dir: .[1]})
    | group_by(.group)
    | map({group: .[0].group, dirs: (map(.dir) | join(" "))})'
  ;;
*)
  echo "usage: $0 [--list|--matrix|--groups|--group <name>]" >&2
  exit 2
  ;;
esac
