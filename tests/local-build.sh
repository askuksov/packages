#!/usr/bin/env bash
# Builds a site from <bundle-dir> inside ubuntu:24.04 with a throwaway
# repository key: the same steps the Publish workflow runs, without the real
# key. The bundle is copied first because signing rewrites the .rpm files.
#
# Usage: local-build.sh <bundle-dir> <site-dir>
# Set REPO_URL=http://<host>:<port> to render kuksov.repo for a local server.
set -euo pipefail

BUNDLE="${1:?usage: local-build.sh <bundle-dir> <site-dir>}"
SITE="${2:?usage: local-build.sh <bundle-dir> <site-dir>}"
[ ! -e "$SITE" ] || { echo "FAIL: $SITE already exists" >&2; exit 1; }
mkdir -p "$SITE"

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BUNDLE_ABS=$(cd "$BUNDLE" && pwd)
SITE_ABS=$(cd "$SITE" && pwd)

# --platform is mandatory on an arm64 host: the packages are amd64.
docker run --rm --platform linux/amd64 \
  -v "$ROOT":/src:ro -v "$BUNDLE_ABS":/bundle:ro -v "$SITE_ABS":/out \
  -e REPO_URL="${REPO_URL:-}" -e DEBIAN_FRONTEND=noninteractive \
  ubuntu:24.04 bash -c '
set -euo pipefail
apt-get update -qq
apt-get install -y -qq --no-install-recommends apt-utils createrepo-c rpm gpg gpgv >/dev/null
export GNUPGHOME=$(mktemp -d)
gpg --batch --passphrase "" --quick-gen-key "Throwaway test repository key" rsa4096 sign never
REPO_GPG_KEY=$(gpg --list-keys --with-colons | awk -F: "/^fpr:/{print \$10; exit}")
export REPO_GPG_KEY
echo "%_gpg_name $REPO_GPG_KEY" >~/.rpmmacros
cp -r /bundle /tmp/bundle
bash /src/scripts/build-site.sh /tmp/bundle /tmp/site
cp -a /tmp/site/. /out/
'
echo "site built at $SITE_ABS"
