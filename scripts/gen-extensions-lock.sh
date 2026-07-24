#!/usr/bin/env bash
# Regenerate extensions.lock from the vendored upstream subtree.
#
# Upstream Bluefin carries its bundled GNOME Shell extensions as git submodules.
# `git subtree add` vendors the tree but does NOT fetch submodule contents — the
# extension directories arrive empty, with only the pinned commit recorded in the
# gitlink tree entry. This script captures those pins (path + url + sha + branch)
# into extensions.lock so scripts/prepare-context.sh can materialise them.
#
# Run this after every `git subtree pull` of upstream, then review the diff — a
# changed sha here is an upstream extension bump, exactly the drift signal the
# subtree model is meant to surface.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

EXT_PREFIX="upstream/system_files/shared/usr/share/gnome-shell/extensions/"

python3 - "$EXT_PREFIX" >extensions.lock <<'PY'
import re, subprocess, sys

ext_prefix = sys.argv[1]

gm = open('upstream/.gitmodules').read()
mods = {}
for blk in re.split(r'(?=\[submodule )', gm):
    p = re.search(r'path\s*=\s*(.+)', blk)
    u = re.search(r'url\s*=\s*(.+)', blk)
    b = re.search(r'branch\s*=\s*(.+)', blk)
    if p and u:
        mods[p.group(1).strip()] = (u.group(1).strip(),
                                    b.group(1).strip() if b else '')

out = subprocess.check_output(
    ['git', 'ls-tree', '-r', 'HEAD', ext_prefix], text=True)
shas = {}
for line in out.splitlines():
    mode, _typ, sha, path = line.split(None, 3)
    if mode == '160000':
        shas[path[len('upstream/'):]] = sha

print("# GNOME extension submodule lock — pinned versions vendored from upstream Bluefin.")
print("# Generated from upstream/.gitmodules + subtree gitlink SHAs by scripts/gen-extensions-lock.sh")
print("# Format: <path-under-system_files/shared>\\t<url>\\t<sha>\\t<branch>")
strip = 'system_files/shared/'
for path in sorted(shas):
    url, branch = mods.get(path, ('', ''))
    if not url:
        print(f"# WARNING: no url for {path}", file=sys.stderr)
        continue
    rel = path[len(strip):] if path.startswith(strip) else path
    print(f"{rel}\t{url}\t{shas[path]}\t{branch}")
PY

echo "==> Wrote extensions.lock ($(grep -c '^usr/' extensions.lock) submodules)"
