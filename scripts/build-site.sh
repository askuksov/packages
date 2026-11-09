#!/usr/bin/env bash
# Builds and signs the whole site from the packages fetch-releases.sh
# downloaded. The order matters: `rpm --addsign` rewrites each package, so it
# runs before createrepo_c indexes them, and the indexes are signed last.
#
# Usage: build-site.sh <bundle-dir> <site-dir>
# Needs REPO_GPG_KEY (fingerprint) with its secret key in the gpg keyring, and
# rpm's %_gpg_name set to the same key.
set -euo pipefail

BUNDLE="${1:?usage: build-site.sh <bundle-dir> <site-dir>}"
SITE="${2:?usage: build-site.sh <bundle-dir> <site-dir>}"
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# The site is built from scratch every time; leftovers from an earlier run
# would be published without coming from sources.txt.
[ ! -e "$SITE" ] || { echo "FAIL: $SITE already exists" >&2; exit 1; }

bash "$HERE/sign-rpm-repo.sh" "$BUNDLE"
bash "$HERE/build-apt-repo.sh" "$BUNDLE" "$SITE"
bash "$HERE/build-rpm-repo.sh" "$BUNDLE" "$SITE"
bash "$HERE/sign-apt-repo.sh" "$SITE"
bash "$HERE/sign-rpm-repo.sh" --metadata "$SITE"
bash "$HERE/export-keyring.sh" "$SITE"
cp "$HERE/../static/index.html" "$SITE/index.html"
bash "$HERE/check-site.sh" "$SITE"
