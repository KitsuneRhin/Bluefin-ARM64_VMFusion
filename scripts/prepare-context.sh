#!/usr/bin/env bash
# Assemble the podman build context from the vendored upstream subtree plus the
# arm64 patch set.
#
# upstream/ is a pristine git subtree of projectbluefin/bluefin and is never
# edited in place — every arm64 delta lives in patches/. This script materialises
# the patched tree into _build_ctx/ (gitignored), which is what podman builds from.
#
# Usage: scripts/prepare-context.sh [context-dir]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CTX="${1:-${REPO_ROOT}/_build_ctx}"
# Persistent bare-ish cache of fetched extension SHAs, reused across context
# rebuilds. Gitignored (_build_* prefix). Override with EXT_CACHE.
EXT_CACHE="${EXT_CACHE:-${REPO_ROOT}/_build_ext_cache}"

cd "$REPO_ROOT"

if [[ ! -d upstream/build_files ]]; then
    echo "error: upstream/ subtree is missing. Run:" >&2
    echo "  git subtree add --prefix=upstream https://github.com/projectbluefin/bluefin main --squash" >&2
    exit 1
fi

echo "==> Rebuilding context at ${CTX}"
rm -rf "$CTX"
mkdir -p "$CTX"

# Only what the ctx stage in the Containerfile actually consumes.
cp -R upstream/build_files "$CTX/build_files"
cp -R upstream/system_files "$CTX/system_files"
cp upstream/image-versions.yml "$CTX/image-versions.yml"

echo "==> Applying arm64 patch set"
shopt -s nullglob
patchset=(patches/*.patch)
if [[ ${#patchset[@]} -eq 0 ]]; then
    echo "error: no patches found in patches/" >&2
    exit 1
fi

for p in "${patchset[@]}"; do
    echo "    $p"
    # Patch paths are a/upstream/build_files/... ; -p2 strips "a/upstream/".
    if ! patch -p2 -d "$CTX" --no-backup-if-mismatch -s <"$p"; then
        echo "error: patch $p failed to apply." >&2
        echo "       upstream/ has probably drifted — rebase the patch set." >&2
        exit 1
    fi
done

# Materialise the bundled GNOME Shell extensions. Upstream carries these as git
# submodules, which the subtree does not fetch (their dirs land empty). We fetch
# each pinned SHA recorded in extensions.lock into the context. Arch-neutral —
# this same step would be required for an amd64 subtree build.
echo "==> Fetching GNOME extension submodules (extensions.lock)"
if [[ ! -f extensions.lock ]]; then
    echo "error: extensions.lock missing. Run scripts/gen-extensions-lock.sh" >&2
    exit 1
fi

EXT_ROOT="$CTX/system_files/shared"
mkdir -p "$EXT_CACHE"

while IFS=$'\t' read -r relpath url sha branch; do
    [[ -z "$relpath" || "$relpath" == \#* ]] && continue
    dest="$EXT_ROOT/$relpath"
    # Cache keyed by sha so an upstream bump fetches fresh but rebuilds reuse.
    cache="$EXT_CACHE/$sha"
    if [[ ! -d "$cache" ]]; then
        echo "    fetch ${relpath##*/} @ ${sha:0:12}"
        tmp="${cache}.tmp.$$"
        rm -rf "$tmp"; mkdir -p "$tmp"
        git -C "$tmp" init -q
        git -C "$tmp" remote add origin "$url"
        # GitHub allows fetching a reachable SHA directly; fall back to the
        # branch tip + checkout if a server refuses by-SHA fetches.
        if ! git -C "$tmp" fetch -q --depth 1 origin "$sha" 2>/dev/null; then
            [[ -n "$branch" ]] && git -C "$tmp" fetch -q --depth 1 origin "$branch"
        fi
        git -C "$tmp" checkout -q "$sha"
        rm -rf "$tmp/.git"
        mv "$tmp" "$cache"
    else
        echo "    cached ${relpath##*/} @ ${sha:0:12}"
    fi
    mkdir -p "$(dirname "$dest")"
    rm -rf "$dest"
    cp -R "$cache" "$dest"
done <extensions.lock

echo "==> Context ready: ${CTX}"
