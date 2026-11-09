#!/usr/bin/env bash
# Signs the apt Release file: InRelease (clearsigned) and Release.gpg (detached).
set -euo pipefail

SITE="${1:?usage: sign-apt-repo.sh <site-dir>}"
KEY="${REPO_GPG_KEY:?set REPO_GPG_KEY to the repository key fingerprint}"
DIST="$SITE/deb/dists/stable"

fail() { echo "FAIL: $*" >&2; exit 1; }

[ -f "$DIST/Release" ] || fail "$DIST/Release missing — run build-apt-repo.sh first"

# An ambiguous key (a uid matching an old and a new key during rotation) makes
# gpg pick one secret key silently. That signature is what every apt client
# trusts, so refuse anything but exactly one matching secret key.
sec_count=$(gpg --list-secret-keys --with-colons -- "$KEY" 2>/dev/null | grep -c '^sec' || true)
[ "$sec_count" -eq 1 ] || fail "REPO_GPG_KEY='$KEY' matched $sec_count secret keys, expected exactly 1"

rm -f "$DIST/InRelease" "$DIST/Release.gpg"
gpg --batch --default-key "$KEY" --clearsign -o "$DIST/InRelease" "$DIST/Release"
gpg --batch --default-key "$KEY" --detach-sign --armor -o "$DIST/Release.gpg" "$DIST/Release"

echo "signed $DIST/{InRelease,Release.gpg}"
