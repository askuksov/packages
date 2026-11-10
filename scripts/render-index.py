#!/usr/bin/env python3
"""Writes <site>/index.html from static/index.html.

The app list comes from the apt index the site was just built with, so the
page shows exactly what the repository serves: one card per package name in
sources.txt, at its highest version. The key fingerprint comes from the
published keyring.

Usage: render-index.py <sources.txt> <site-dir>
"""
import html
import pathlib
import re
import subprocess
import sys


def fail(msg):
    sys.exit(f"FAIL: {msg}")


def read_stanzas(path):
    """Parses a Debian Packages file into a list of {field: value} dicts."""
    stanzas = []
    for block in path.read_text(encoding="utf-8").split("\n\n"):
        fields, last = {}, None
        for line in block.splitlines():
            if line.startswith((" ", "\t")) and last:
                fields[last] += "\n" + line.strip()
            elif ":" in line:
                last, value = line.split(":", 1)
                fields[last] = value.strip()
        if "Package" in fields:
            stanzas.append(fields)
    return stanzas


def newer(a, b):
    return subprocess.run(["dpkg", "--compare-versions", a, "gt", b]).returncode == 0


def fingerprint(keyring):
    out = subprocess.run(
        ["gpg", "--show-keys", "--with-colons", str(keyring)],
        check=True, capture_output=True, text=True,
    ).stdout
    fprs = [l.split(":")[9] for l in out.splitlines() if l.startswith("fpr:")]
    if not fprs:
        fail(f"no key in {keyring}")
    groups = [fprs[0][i:i + 4] for i in range(0, 40, 4)]
    return " ".join(groups[:5]) + "  " + " ".join(groups[5:])


def block(command):
    return f'        <div class="block"><pre>{html.escape(command)}</pre></div>'


def card(name, repo, stanza):
    version = stanza.get("Version", "")
    summary = stanza.get("Description", "").split("\n", 1)[0]
    depends = stanza.get("Depends", "")
    meta = []
    glibc = re.search(r"libc6 \(>= ([0-9.]+)\)", depends)
    if glibc:
        meta.append(f"Needs glibc {glibc.group(1)} or newer")
    e = html.escape
    lines = [
        '      <article class="app">',
        '        <div class="app-head">',
        f'          <span class="app-name mono">{e(name)}</span>',
        f'          <span class="app-version">{e(version)}</span>',
        f'          <a class="app-link" href="https://github.com/{e(repo)}">Source</a>',
        '        </div>',
        f'        <p class="app-desc">{e(summary)}</p>',
        f'        <p class="app-meta">{e(" · ".join(meta))}</p>' if meta else "",
        block(f"sudo apt install {name}"),
        block(f"sudo dnf --setopt=assumeyes=False install {name}"),
        '      </article>',
    ]
    return "\n".join(l for l in lines if l)


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: render-index.py <sources.txt> <site-dir>")
    sources, site = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
    template = pathlib.Path(__file__).resolve().parent.parent / "static" / "index.html"

    stanzas = read_stanzas(site / "deb/dists/stable/main/binary-amd64/Packages")
    best = {}
    for s in stanzas:
        name = s["Package"]
        if name not in best or newer(s.get("Version", ""), best[name].get("Version", "")):
            best[name] = s

    cards, seen = [], set()
    for line in sources.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        repo, _tag, _fpr, names = line.split()
        for name in names.split(","):
            if name in seen:
                continue
            if name not in best:
                fail(f"{name} is in sources.txt but not in the apt index")
            seen.add(name)
            cards.append(card(name, repo, best[name]))
    if not cards:
        fail("no apps to list")

    page = template.read_text(encoding="utf-8")
    for marker in ("{{FINGERPRINT}}", "{{APPS}}"):
        if marker not in page:
            fail(f"{template} has no {marker}")
    page = page.replace("{{FINGERPRINT}}", fingerprint(site / "kuksov-archive-keyring.gpg"))
    page = page.replace("{{APPS}}", "\n".join(cards))
    (site / "index.html").write_text(page, encoding="utf-8")
    print(f"index.html lists {len(cards)} app(s)")


if __name__ == "__main__":
    main()
