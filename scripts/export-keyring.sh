#!/usr/bin/env bash
# Exports the public repository key in both encodings package managers need:
#   kuksov-archive-keyring.gpg  binary   -> apt  signed-by=
#   kuksov-archive-keyring.asc  armored  -> dnf  gpgkey=
set -euo pipefail

SITE="${1:?usage: export-keyring.sh <site-dir>}"
KEY="${REPO_GPG_KEY:?set REPO_GPG_KEY to the repository key fingerprint}"

fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir -p "$SITE"
GPG_OUT="$SITE/kuksov-archive-keyring.gpg"
ASC_OUT="$SITE/kuksov-archive-keyring.asc"

# Export to temp names and move into place only after the checks pass, so a
# failed run never leaves a wrong trust root where users will fetch it. The
# leading dot keeps a leftover temp file out of globs.
TMP_GPG="$SITE/.keyring.gpg.tmp$$"
TMP_ASC="$SITE/.keyring.asc.tmp$$"
trap 'rm -f "$TMP_GPG" "$TMP_ASC"' EXIT

gpg --export -- "$KEY" >"$TMP_GPG"
gpg --export --armor -- "$KEY" >"$TMP_ASC"

# gpg exits 0 with empty output for an unknown key.
[ -s "$TMP_GPG" ] || fail "empty keyring export"
[ -s "$TMP_ASC" ] || fail "empty armored export"

# An ambiguous key makes gpg export every match, widening what apt and dnf
# trust. Refuse anything but exactly one public key.
key_count=$(gpg --show-keys --with-colons "$TMP_GPG" | grep -c '^pub' || true)
[ "$key_count" -eq 1 ] || fail "REPO_GPG_KEY='$KEY' matched $key_count keys, expected exactly 1"

mv -f "$TMP_GPG" "$GPG_OUT"
mv -f "$TMP_ASC" "$ASC_OUT"

echo "exported $KEY:"
gpg --show-keys "$GPG_OUT" | sed 's/^/  /'
