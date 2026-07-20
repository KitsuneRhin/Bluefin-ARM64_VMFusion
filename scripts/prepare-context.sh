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

echo "==> Context ready: ${CTX}"
