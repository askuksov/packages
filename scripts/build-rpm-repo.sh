#!/usr/bin/env bash
# Builds the dnf repository from every .rpm under <bundle-dir>.
# The .rpm files must already be signed (sign-rpm-repo.sh): createrepo_c
# hashes them as they are, and signing rewrites the file.
set -euo pipefail

BUNDLE_DIR="${1:?usage: build-rpm-repo.sh <bundle-dir> <site-dir>}"
SITE="${2:?usage: build-rpm-repo.sh <bundle-dir> <site-dir>}"

fail() { echo "FAIL: $*" >&2; exit 1; }

ARCH_DIR="$SITE/rpm/stable/x86_64"
mkdir -p "$ARCH_DIR"

count=0
while IFS= read -r -d '' f; do
  [ ! -e "$ARCH_DIR/$(basename "$f")" ] || fail "$(basename "$f") comes from more than one release"
  cp "$f" "$ARCH_DIR/"
  count=$((count + 1))
done < <(find "$BUNDLE_DIR" -name '*.rpm' -print0)
[ "$count" -gt 0 ] || fail "no .rpm under $BUNDLE_DIR"

createrepo_c --general-compress-type=gz "$ARCH_DIR"

# The .repo file users install must name the host this tree is served from.
# REPO_URL defaults to production; a local end-to-end test points it at its
# own server, or dnf would fetch from production and test nothing local.
SERVE_URL="${REPO_URL:-https://packages.kuksov.dev}"
sed "s|https://packages\.kuksov\.dev|$SERVE_URL|g" \
  "$(dirname "$0")/kuksov.repo" >"$SITE/rpm/kuksov.repo"

echo "built dnf metadata for $count package(s) at $ARCH_DIR"
