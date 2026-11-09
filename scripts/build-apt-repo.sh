#!/usr/bin/env bash
# Builds the unsigned apt repository tree from every .deb under <bundle-dir>.
# Each package goes to pool/main/<first letter>/<package name>/, so several
# apps share one pool and one index.
set -euo pipefail

BUNDLE_DIR="${1:?usage: build-apt-repo.sh <bundle-dir> <site-dir>}"
SITE="${2:?usage: build-apt-repo.sh <bundle-dir> <site-dir>}"

fail() { echo "FAIL: $*" >&2; exit 1; }

DEB_ROOT="$SITE/deb"
mkdir -p "$DEB_ROOT/dists/stable/main/binary-amd64"

count=0
while IFS= read -r -d '' f; do
  pkg=$(dpkg-deb -f "$f" Package)
  [[ "$pkg" =~ ^[a-z0-9][a-z0-9+.-]+$ ]] || fail "$f: bad Package name '$pkg'"
  dest="$DEB_ROOT/pool/main/${pkg:0:1}/$pkg"
  mkdir -p "$dest"
  # Two releases shipping the same file name would silently replace one
  # another; the index would then describe only the survivor.
  [ ! -e "$dest/$(basename "$f")" ] || fail "$(basename "$f") comes from more than one release"
  cp "$f" "$dest/"
  count=$((count + 1))
done < <(find "$BUNDLE_DIR" -name '*.deb' -print0)
[ "$count" -gt 0 ] || fail "no .deb under $BUNDLE_DIR"

# Run from the deb root so Filename: comes out relative to the suite root
# (pool/main/...). An absolute Filename makes every client 404.
cd "$DEB_ROOT"
apt-ftparchive packages pool >dists/stable/main/binary-amd64/Packages
gzip -9cn dists/stable/main/binary-amd64/Packages >dists/stable/main/binary-amd64/Packages.gz
grep -q '^Filename: pool/' dists/stable/main/binary-amd64/Packages ||
  fail "Packages has no relative Filename: entries"

apt-ftparchive \
  -o APT::FTPArchive::Release::Origin=kuksov.dev \
  -o APT::FTPArchive::Release::Label=kuksov.dev \
  -o APT::FTPArchive::Release::Suite=stable \
  -o APT::FTPArchive::Release::Codename=stable \
  -o APT::FTPArchive::Release::Architectures=amd64 \
  -o APT::FTPArchive::Release::Components=main \
  -o APT::FTPArchive::Release::Description="Packages from kuksov.dev" \
  release dists/stable >dists/stable/Release

echo "built unsigned apt repo with $count package(s) at $DEB_ROOT"
