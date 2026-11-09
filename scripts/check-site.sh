#!/usr/bin/env bash
# Last gate before deploy: verifies the built site the way a client will,
# using only the public key the site itself publishes.
set -euo pipefail

SITE="${1:?usage: check-site.sh <site-dir>}"
SITE=$(cd "$SITE" && pwd)

fail() { echo "FAIL: $*" >&2; exit 1; }

KEYRING="$SITE/kuksov-archive-keyring.gpg"
DIST="$SITE/deb/dists/stable"
MD="$SITE/rpm/stable/x86_64/repodata/repomd.xml"

for f in "$KEYRING" "$SITE/kuksov-archive-keyring.asc" "$SITE/rpm/kuksov.repo" \
  "$DIST/Release" "$DIST/Release.gpg" "$DIST/InRelease" "$MD" "$MD.asc"; do
  [ -f "$f" ] || fail "$f missing"
done

gpgv --keyring "$KEYRING" "$DIST/Release.gpg" "$DIST/Release" 2>/dev/null ||
  fail "Release.gpg does not verify against Release with the published key"

# A clearsigned InRelease stays a valid signature after Release changes under
# it. Only comparing its signed text with the current Release catches that.
gpgv --keyring "$KEYRING" -o - "$DIST/InRelease" 2>/dev/null | cmp -s - "$DIST/Release" ||
  fail "InRelease does not verify, or does not match Release"

gpgv --keyring "$KEYRING" "$MD.asc" "$MD" 2>/dev/null ||
  fail "repomd.xml.asc does not verify against repomd.xml with the published key"

# GitHub Pages refuses a site over 1 GB. Fail here, with a clear message,
# rather than in the deploy step.
size_mb=$(( $(du -sk "$SITE" | cut -f1) / 1024 ))
[ "$size_mb" -le 950 ] || fail "site is ${size_mb} MB; GitHub Pages allows 1 GB — drop old releases from sources.txt"

echo "site OK (${size_mb} MB)"
