# packages.kuksov.dev

apt and dnf repositories for apps by Oleksandr Kuksov, served from GitHub
Pages at <https://packages.kuksov.dev>.

Packages are x86_64 and need glibc 2.39 or newer: Ubuntu 24.04+, Debian 13+,
Fedora 40+.

## Install

### Debian / Ubuntu

```sh
sudo apt install -y curl
sudo install -d -m 0755 /etc/apt/keyrings
sudo curl -fsSLo /etc/apt/keyrings/kuksov.gpg https://packages.kuksov.dev/kuksov-archive-keyring.gpg
gpg --show-keys /etc/apt/keyrings/kuksov.gpg   # must show EED9 1C1A 7BF9 745A 985C  19AA D63F 9938 F413 FDE5
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/kuksov.gpg] https://packages.kuksov.dev/deb stable main" \
  | sudo tee /etc/apt/sources.list.d/kuksov.list
sudo apt update
sudo apt install kokos
```

### Fedora

```sh
sudo tee /etc/yum.repos.d/kuksov.repo >/dev/null <<'EOF'
[kuksov]
name=kuksov.dev packages
baseurl=https://packages.kuksov.dev/rpm/stable/$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.kuksov.dev/kuksov-archive-keyring.asc
metadata_expire=6h
EOF
sudo dnf install kokos
```

The repository definition is written out in full rather than downloaded, so
`gpgcheck=1` and `repo_gpgcheck=1` come from these instructions, not from the
server. dnf asks you to confirm the key on first install. The same file is
also published at `https://packages.kuksov.dev/rpm/kuksov.repo`.

### Repository key

Packages and indexes are signed with the repository key:

```
EED9 1C1A 7BF9 745A 985C  19AA D63F 9938 F413 FDE5
kuksov.dev package repository (RSA 4096)
```

Check it before you trust it:

```sh
gpg --show-keys --with-fingerprint /etc/apt/keyrings/kuksov.gpg
```

This key is not the key that signs app releases. Each app's release key is
listed in that app's `SECURITY.md`.

## How it works

`sources.txt` lists the releases the site serves. On every push to `main`
the [Publish](.github/workflows/publish.yml) workflow:

1. downloads the `.deb` and `.rpm` files of each listed release, and refuses
   any release whose `SHA256SUMS.asc` is not signed by the key pinned for it
   in `sources.txt` (public keys in `keys/release/`), or whose packages have
   another name or a version other than the tag's;
2. signs the `.rpm` files, builds the apt and dnf indexes, and signs them with
   the repository key;
3. verifies the result with the published public key and deploys the whole
   site to GitHub Pages at once.

The site is rebuilt from scratch on every run, so no package is stored in git.

## Adding a release

1. Publish the app release with a signed `SHA256SUMS` as usual.
2. Add a line to `sources.txt`:
   `<owner/repo> <tag> <release key fingerprint> <package names>`.
   For a new app, also add its public release key as
   `keys/release/<fingerprint>.asc`.
3. Drop old lines so each app keeps one or two versions: GitHub Pages serves at
   most 1 GB. Older versions stay on the app's GitHub Releases page.
4. Push to `main` and watch the Publish workflow.

## Setup

- Secret `REPO_GPG_PRIVATE_KEY`: the repository secret key, armored, without a
  passphrase.
- Variable `REPO_GPG_FPR`: its fingerprint.
- Settings › Pages › Source: GitHub Actions. Custom domain
  `packages.kuksov.dev`, Enforce HTTPS.
- DNS: `packages` CNAME `askuksov.github.io`, DNS only (no proxy).
- `kuksov.dev` verified in the account's Pages settings, so no other account
  can claim the subdomain.

## Tests

`tests/` holds the checks for the tooling. They run in Docker and are not part
of the workflow:

- `make-fixture.sh <dir>` builds small `kokos` .deb and .rpm fixtures;
- `local-build.sh <bundle-dir> <site-dir>` builds a site from a bundle with a
  throwaway key;
- `test-apt-repo.sh <site-dir>` and `test-rpm-repo.sh <site-dir>` install from
  that site with real apt and dnf clients;
- `test-repofile.sh [<site-dir>]` checks `kuksov.repo`;
- `e2e-install.sh` installs from the live site.

## Licence

MIT
