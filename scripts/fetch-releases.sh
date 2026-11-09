#!/usr/bin/env bash
# Downloads the .deb and .rpm files of every release in sources.txt and
# proves each one is the file the app's maintainer signed: SHA256SUMS.asc must
# carry a good signature from the fingerprint pinned in sources.txt, and every
# package must be listed in SHA256SUMS with a matching hash.
#
# Usage: fetch-releases.sh <sources.txt> <keys-dir> <out-dir>
# Needs gh (GH_TOKEN in CI), gpg, gpgv, sha256sum.
set -euo pipefail

SOURCES="${1:?usage: fetch-releases.sh <sources.txt> <keys-dir> <out-dir>}"
KEYS="${2:?usage: fetch-releases.sh <sources.txt> <keys-dir> <out-dir>}"
OUT="${3:?usage: fetch-releases.sh <sources.txt> <keys-dir> <out-dir>}"

fail() { echo "FAIL: $*" >&2; exit 1; }

[ -f "$SOURCES" ] || fail "no such file $SOURCES"
[ ! -e "$OUT" ] || fail "$OUT already exists — fetch into a fresh directory"
mkdir -p "$OUT"

count=0
lineno=0
while IFS= read -r line || [ -n "$line" ]; do
  lineno=$((lineno + 1))
  case "$line" in ''|'#'*) continue ;; esac
  read -r repo tag fpr extra <<<"$line"
  [ -z "${extra:-}" ] || fail "$SOURCES:$lineno: expected 3 fields, got more"
  [[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || fail "$SOURCES:$lineno: bad repo '$repo'"
  [[ "$tag" =~ ^[A-Za-z0-9_.+-]+$ ]] || fail "$SOURCES:$lineno: bad tag '$tag'"
  [[ "${fpr:-}" =~ ^[0-9A-F]{40}$ ]] || fail "$SOURCES:$lineno: fingerprint must be 40 upper-case hex digits"

  keyfile="$KEYS/$fpr.asc"
  [ -f "$keyfile" ] || fail "$SOURCES:$lineno: no public key at $keyfile"

  dir="$OUT/${repo//\//_}_$tag"
  mkdir "$dir"
  echo "== $repo $tag"
  gh release download "$tag" -R "$repo" -D "$dir" \
    -p '*.deb' -p '*.rpm' -p 'SHA256SUMS' -p 'SHA256SUMS.asc'

  [ -f "$dir/SHA256SUMS" ] && [ -f "$dir/SHA256SUMS.asc" ] ||
    fail "$repo $tag: release has no SHA256SUMS and SHA256SUMS.asc"

  # Verify against a keyring holding ONLY the pinned key, then demand that the
  # good signature names that primary key: a valid signature from some other
  # key must not count.
  ring="$dir/.keyring.gpg"
  gpg --dearmor <"$keyfile" >"$ring"
  status=$(gpgv --status-fd 1 --keyring "$ring" "$dir/SHA256SUMS.asc" "$dir/SHA256SUMS" 2>/dev/null) ||
    fail "$repo $tag: SHA256SUMS.asc does not verify with $fpr"
  awk -v f="$fpr" '$2 == "VALIDSIG" && $NF == f { ok = 1 } END { exit !ok }' <<<"$status" ||
    fail "$repo $tag: SHA256SUMS is not signed by $fpr"
  rm -f "$ring"

  # Every package must be listed: --ignore-missing alone would pass a file
  # that SHA256SUMS never mentions.
  listed=$(sed -E 's/^[0-9a-f]{64} [ *]//' "$dir/SHA256SUMS")
  pkgs=0
  for f in "$dir"/*.deb "$dir"/*.rpm; do
    [ -e "$f" ] || continue
    grep -Fxq -- "$(basename "$f")" <<<"$listed" || fail "$repo $tag: $(basename "$f") is not in SHA256SUMS"
    pkgs=$((pkgs + 1))
  done
  [ "$pkgs" -gt 0 ] || fail "$repo $tag: release has no .deb or .rpm"
  (cd "$dir" && sha256sum --quiet --ignore-missing -c SHA256SUMS) || fail "$repo $tag: checksum mismatch"

  rm -f "$dir/SHA256SUMS" "$dir/SHA256SUMS.asc"
  echo "verified $pkgs package(s) from $repo $tag"
  count=$((count + 1))
done <"$SOURCES"

[ "$count" -gt 0 ] || fail "$SOURCES lists no releases"
echo "fetched $count release(s) into $OUT"
