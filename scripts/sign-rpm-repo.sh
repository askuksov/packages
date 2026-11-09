#!/usr/bin/env bash
# Signs every .rpm in the bundle dir, then the repo metadata.
# Usage: sign-rpm-repo.sh <bundle-dir>            # phase 1, before createrepo_c
#        sign-rpm-repo.sh --metadata <site-dir>   # phase 2, after createrepo_c
# Phase 1 needs rpm's %_gpg_name set to REPO_GPG_KEY (e.g. in ~/.rpmmacros).
set -euo pipefail

KEY="${REPO_GPG_KEY:?set REPO_GPG_KEY to the repository key fingerprint}"

fail() { echo "FAIL: $*" >&2; exit 1; }

# Checked before either phase: the --metadata branch exits early, and a
# keyring mid-rotation must not sign repomd.xml with the wrong key.
sec_count=$(gpg --list-secret-keys --with-colons -- "$KEY" 2>/dev/null | grep -c '^sec' || true)
[ "$sec_count" -eq 1 ] || fail "REPO_GPG_KEY='$KEY' matched $sec_count secret keys, expected exactly 1"

if [ "${1:-}" = "--metadata" ]; then
  SITE="${2:?usage: sign-rpm-repo.sh --metadata <site-dir>}"
  MD="$SITE/rpm/stable/x86_64/repodata/repomd.xml"
  [ -f "$MD" ] || fail "$MD missing — run build-rpm-repo.sh first"
  rm -f "$MD.asc"
  gpg --batch --default-key "$KEY" --detach-sign --armor -o "$MD.asc" "$MD"
  echo "signed $MD.asc"
  exit 0
fi

BUNDLE_DIR="${1:?usage: sign-rpm-repo.sh <bundle-dir>}"

# Ask rpm what it resolved rather than grepping a macro file: rpm versions
# differ in which file they read (~/.rpmmacros vs ~/.config/rpm/macros).
[ "$(rpm --eval '%{_gpg_name}')" != '%{_gpg_name}' ] || fail "rpm has no %_gpg_name configured"

# Lower-case fingerprint, to prove the signature that lands is ours.
FPR=$(gpg --fingerprint --with-colons -- "$KEY" | awk -F: '/^fpr:/{print tolower($10); exit}')
[ -n "$FPR" ] || fail "cannot resolve a fingerprint for $KEY"

[ -d "$BUNDLE_DIR" ] || fail "no such directory $BUNDLE_DIR"

# `rpm --addsign` rewrites each package, so its checksum changes. On a tree
# createrepo_c already indexed, repomd.xml would then describe checksums that
# no longer exist, and the failure would surface only at the user's
# `dnf install`. Refuse an indexed tree.
if find "$BUNDLE_DIR" -type d -name repodata -print -quit | grep -q .; then
  fail "$BUNDLE_DIR already contains a repodata/ index; sign packages BEFORE createrepo_c runs"
fi

rpm_count=$(find "$BUNDLE_DIR" -name '*.rpm' | wc -l | tr -d ' ')
[ "$rpm_count" -gt 0 ] || fail "no .rpm found under $BUNDLE_DIR"

while IFS= read -r -d '' f; do
  rpm --addsign "$f"
  # rpm -Kv exits nonzero for the expected NOKEY state too (signed, public key
  # not imported), so read its output instead of its status.
  out=$(rpm -Kv "$f" 2>&1) || true
  # NOTFOUND lines appear for every algorithm rpm did not find, even on a
  # signed package, so they cannot tell signed from unsigned. A verdict line
  # can: NOKEY = signed, key not imported; "key fingerprint" = signed and
  # verified. Never match a bare "OK": "NOKEY" and the digest lines contain it.
  case "$out" in
    *NOKEY*|*"key fingerprint"*) ;;
    *) echo "$out"; fail "$f carries no signature" ;;
  esac
  # In the NOKEY state rpm prints a truncated key id (8 hex on rpm 4.18,
  # 16 on rpm 6); all forms are the tail of the fingerprint.
  case "$out" in
    *"$FPR"*|*"${FPR: -16}"*|*"${FPR: -8}"*) ;;
    *) echo "$out"; fail "$f is not signed by $FPR" ;;
  esac
  echo "signed $f"
done < <(find "$BUNDLE_DIR" -name '*.rpm' -print0)
