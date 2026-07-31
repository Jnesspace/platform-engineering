#!/usr/bin/env bash
#
# Install a third-party binary at a pinned version and refuse it unless its
# sha256 matches the value recorded below. Prints the absolute path.
#
# Why bother, when the version is already pinned: a git tag can be moved and a
# release asset can be replaced in place. Pinning the version alone moves the
# supply-chain risk from "any release" to "whoever can push to that release",
# which for a repo whose tracked branch runs with Space-admin is not far enough.
# Third-party *actions* get pinned to a commit SHA in the workflow; third-party
# *tarballs* get pinned here.
#
# Shared by CI and .pre-commit-config.yaml so a developer's gitleaks is byte-for-
# byte the one the merge gate uses.
#
# Usage: install-pinned.sh gitleaks | actionlint
# Env:   PINNED_BIN_DIR — where to install (default: user cache dir)

set -euo pipefail

BIN_DIR="${PINNED_BIN_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/platform-engineering/bin}"

GITLEAKS_VERSION=8.30.1
ACTIONLINT_VERSION=1.7.12

tool="${1:?usage: $0 <gitleaks|actionlint>}"

case "$(uname -s)" in
Linux) os=linux ;;
Darwin) os=darwin ;;
*) echo "unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac
case "$(uname -m)" in
x86_64 | amd64) arch=amd64 ;;
arm64 | aarch64) arch=arm64 ;;
*) echo "unsupported arch: $(uname -m)" >&2; exit 1 ;;
esac

case "$tool:$os:$arch" in
# gitleaks names the 64-bit x86 build "x64", not "amd64".
gitleaks:linux:amd64)   ver=$GITLEAKS_VERSION;   asset="gitleaks_${ver}_linux_x64.tar.gz";     sha=551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb ;;
gitleaks:linux:arm64)   ver=$GITLEAKS_VERSION;   asset="gitleaks_${ver}_linux_arm64.tar.gz";   sha=e4a487ee7ccd7d3a7f7ec08657610aa3606637dab924210b3aee62570fb4b080 ;;
gitleaks:darwin:amd64)  ver=$GITLEAKS_VERSION;   asset="gitleaks_${ver}_darwin_x64.tar.gz";    sha=dfe101a4db2255fc85120ac7f3d25e4342c3c20cf749f2c20a18081af1952709 ;;
gitleaks:darwin:arm64)  ver=$GITLEAKS_VERSION;   asset="gitleaks_${ver}_darwin_arm64.tar.gz";  sha=b40ab0ae55c505963e365f271a8d3846efbc170aa17f2607f13df610a9aeb6a5 ;;
actionlint:linux:amd64) ver=$ACTIONLINT_VERSION; asset="actionlint_${ver}_linux_amd64.tar.gz"; sha=8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8 ;;
actionlint:linux:arm64) ver=$ACTIONLINT_VERSION; asset="actionlint_${ver}_linux_arm64.tar.gz"; sha=325e971b6ba9bfa504672e29be93c24981eeb1c07576d730e9f7c8805afff0c6 ;;
actionlint:darwin:amd64) ver=$ACTIONLINT_VERSION; asset="actionlint_${ver}_darwin_amd64.tar.gz"; sha=5b44c3bc2255115c9b69e30efc0fecdf498fdb63c5d58e17084fd5f16324c644 ;;
actionlint:darwin:arm64) ver=$ACTIONLINT_VERSION; asset="actionlint_${ver}_darwin_arm64.tar.gz"; sha=aba9ced2dee8d27fecca3dc7feb1a7f9a52caefa1eb46f3271ea66b6e0e6953f ;;
*) echo "no pinned build recorded for $tool on $os/$arch" >&2; exit 1 ;;
esac

case "$tool" in
gitleaks) url="https://github.com/gitleaks/gitleaks/releases/download/v${ver}/${asset}" ;;
actionlint) url="https://github.com/rhysd/actionlint/releases/download/v${ver}/${asset}" ;;
esac

# Version-stamped filename: a cached binary from an older pin must never be
# mistaken for the current one.
dest="$BIN_DIR/$tool-$ver"
if [ -x "$dest" ]; then
  printf '%s\n' "$dest"
  exit 0
fi

mkdir -p "$BIN_DIR"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

curl -fsSL --retry 3 -o "$tmp/$asset" "$url"

if command -v sha256sum >/dev/null 2>&1; then
  actual="$(sha256sum "$tmp/$asset" | cut -d' ' -f1)"
else
  actual="$(shasum -a 256 "$tmp/$asset" | cut -d' ' -f1)"
fi
if [ "$actual" != "$sha" ]; then
  # Loud and fatal: a checksum mismatch is either a moved release or a
  # compromised one, and there is no version of this worth continuing past.
  echo "checksum mismatch for $asset" >&2
  echo "  expected $sha" >&2
  echo "  actual   $actual" >&2
  exit 1
fi

tar -xzf "$tmp/$asset" -C "$tmp" "$tool"
install -m 0755 "$tmp/$tool" "$dest"
printf '%s\n' "$dest"
