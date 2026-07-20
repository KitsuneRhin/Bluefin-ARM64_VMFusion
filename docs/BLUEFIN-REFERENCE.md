# Upstream Bluefin — verified reference

Facts gathered by direct inspection of live registries and upstream source on
**2026-07-20**. Recorded so downstream work doesn't re-derive them.

Everything here was measured, not assumed. Re-verify before relying on a digest.

---

## 1. Org and repo map

Bluefin moved from `ublue-os` to the **`projectbluefin`** GitHub org. Repos that matter:

| Repo | Purpose |
|---|---|
| `projectbluefin/bluefin` | Main image build. The source of truth for `build_files/`. |
| `projectbluefin/actions` | Reusable composite actions for bootc builders. Use these. |
| `projectbluefin/common` | Shared OCI layer, consumed via `COPY --from`. Multi-arch. |
| `projectbluefin/finpilot` | "Build your own Bluefin" template. Correct starting point for derivatives. |
| `projectbluefin/iso` | ISO construction. |
| `projectbluefin/testsuite`, `lab` | QA via Argo Workflows + KubeVirt. Cluster-scale; usually out of scope. |
| `projectbluefin/dakota` | GNOME-OS-based Bluefin built from source via BuildStream. **Alpha.** |
| `projectbluefin/bluefin-lts` | CentOS bootc based. amd64-only. |
| `ublue-os/brew` | Homebrew layer. Multi-arch. Still under `ublue-os`. |
| `ublue-os/akmods` | Prebuilt kernel modules + kernel cache. **amd64-only.** |

## 2. Published image state

Measured from GHCR/Quay manifests and config blobs.

### 2.1 Bluefin streams — all Fedora 44, all amd64-only

| Tag | `image.version` | `ostree.linux` |
|---|---|---|
| `stable` | `testing-44.20260720` | `7.1.3-201.fc44` |
| `testing` | `testing-44.20260720.6` | `7.1.4-200.fc44` |
| `latest` | `testing-44.20260608.4` | `7.0.11-200.fc44` |
| `gts` | `44.20260606.1` | `7.0.8-200.fc44` |

Two traps here:

- `stable` currently carries a **`testing-`** version string. Stable and testing are
  near-identical right now. **Pin by digest, not by tag name.**
- No F43 tags survive. Their `ghcr-cleanup` action prunes at 90 days, so "pin to an older
  Fedora release" is never a durable strategy against this registry.

`bluefin:stable` and `bluefin-lts:stable` both report `architecture: amd64` — single
manifest, no index. **There is no arm64 Bluefin.**

### 2.2 Multi-arch status of the composable layers

| Image | amd64 | arm64 |
|---|---|---|
| `quay.io/fedora-ostree-desktops/silverblue:44` | ✅ | ✅ |
| `ghcr.io/projectbluefin/common:latest` | ✅ | ✅ |
| `ghcr.io/ublue-os/brew:latest` | ✅ | ✅ |
| `quay.io/centos-bootc/bootc-image-builder:latest` | ✅ | ✅ |
| `ghcr.io/ublue-os/akmods:main-44` | ✅ | ❌ |
| `ghcr.io/projectbluefin/bluefin:stable` | ✅ | ❌ |

### 2.3 Digests as of 2026-07-20

Starting points for pinning. **These move — treat as a snapshot, let Renovate maintain.**

```
quay.io/fedora-ostree-desktops/silverblue:44
  index  sha256:c959d94deb6ec721f7052b87316e5a3f1dd5529f33692e92ef326984aa92a187
  arm64  sha256:d921093409d7fe80d2b03ccbadbedb088f690b21e359859d0068c665e6ff4bf6

ghcr.io/projectbluefin/common:latest
  index  sha256:633ae6efa2f28f451812586cfeb5162d7b70054dda3e25510abdb3c6afa13be8
  arm64  sha256:497cb90e7d30e1a93fda67c112b3146fb43e5e64a774301d2d7025cb57d1e90a

ghcr.io/ublue-os/brew:latest
  index  sha256:14ad3acb89bea0a7d98cacc206a4f590efcb794b7da7385bbeba4ed943289ad4
  arm64  sha256:26fc5b56dad4aafaef39bfd1bee5657204fff31b5fb43c8af3646b3af71b94cf
```

### 2.4 Trap: upstream's `image-versions.yml` pins `common` to an amd64 child

Verified 2026-07-20. `upstream/image-versions.yml` pins:

```
common  sha256:2dfc002c2e9867c120a481d30fad5e7e71294b24c6682adc362c70a8459241a5
brew    sha256:14ad3acb89bea0a7d98cacc206a4f590efcb794b7da7385bbeba4ed943289ad4
```

The `brew` digest is a **multi-arch index** and is safe to reuse. The `common` digest is
**not an index** — it is the amd64 child manifest (`architecture: amd64` in its config
blob). **Do not copy the `common` pin out of `image-versions.yml` into an arm64 build.**

The corresponding index is `sha256:633ae6ef...` (§2.3), which currently *is* `:latest` and
resolves to:

```
amd64  sha256:2dfc002c2e9867c120a481d30fad5e7e71294b24c6682adc362c70a8459241a5
arm64  sha256:497cb90e7d30e1a93fda67c112b3146fb43e5e64a774301d2d7025cb57d1e90a
```

Our `Containerfile` pins the arm64 children directly so the arch is explicit rather than
dependent on podman's platform resolution.

Also re-verified 2026-07-20: the Silverblue 44 arm64 child digest in §2.3
(`sha256:d9210934...`) is still the live arm64 entry of the `:44` index.

## 3. Third-party repo arm64 coverage

| Source | arm64 | Evidence |
|---|---|---|
| COPR `ublue-os/packages` | ✅ | `fedora-44-aarch64` chroot present |
| COPR `ublue-os/staging` | ✅ | `fedora-44-aarch64` chroot present |
| negativo17 `multimedia/fedora-44` | ✅ | 556 aarch64 RPMs |
| Tailscale | ✅ | `stable/fedora/aarch64/repodata/repomd.xml` → 200 |

Note: directory listings on `pkgs.tailscale.com` return 404 for all arches — that is
listing denial, not absence. Probe `repodata/repomd.xml` instead.

## 4. `projectbluefin/actions` catalogue

Under `bootc-build/`. Pin each to a commit SHA; let Renovate bump.

**Setup:** `setup-runner` (podman, storage, tools), `preflight` (validate runner env)
**Caching:** `dnf-cache` (with permissions workaround), `ghcr-cleanup` (prune old images)
**Matrix:** `detect-changes` (changed paths → image-flavor build matrix)
**Validation:** `validate-pr` (just check, shellcheck, hadolint, pre-commit)
**Tagging/push:** `generate-tags`, `push-image` (retry + digest capture), `create-manifest`
(multi-arch index)
**Security:** `sign-and-publish` (cosign + SBOM + SLSA Build L2 provenance),
`scan-image` (Trivy CVE → SARIF, auto-files issues)
**Optimization:** `rechunk` (rpm-ostree, for OTA deltas), `chunka` (OCI-native, no rpm-ostree)
**Release:** `generate-release-notes` (git-cliff), `create-release`, `apply-pkg-intervals`

These are written for amd64 Bluefin. Verify on arm64 before assuming drop-in —
`rechunk` and `scan-image` are the likeliest to need accommodation.

## 5. Upstream build pattern

From `projectbluefin/bluefin/Containerfile`:

- Base `quay.io/fedora-ostree-desktops/silverblue:44`, cosign-verified, digest-pinned
- `common` and `brew` composed via `COPY --from`, digests pinned in `image-versions.yml`
- **Two-stage cache split**: stage 1 mounts only `build_files/`, stage 2 only
  `system_files/`. A `system_files`-only change gets a stage-1 cache hit worth 20–80 min.
  **Preserve this split in any derivative.**
- Final gate: `RUN bootc container lint --fatal-warnings --skip nonempty-boot`

### 5.1 `build_files/` inventory

```
base/00-image-info.sh          base/17-cleanup.sh
base/03-packages.sh            base/18-workarounds.sh
base/04-install-kernel-akmods.sh   base/19-initramfs.sh
base/05-override-install.sh    base/20-tests.sh
                               base/21-container-native-iso.sh
packages/base.toml             shared/{build,package-lib,read-packages,copr-helpers,
                               validate-repos,clean-stage,disable-repos,
                               build-gnome-extensions,finalize-gnome-extensions}.sh
```

### 5.2 `packages/base.toml` structure

Sections: `[multimedia_overrides]`, `[fedora]`, `[fedora_v42]`, `[fedora_v43]`,
`[fedora_v44]`, `[excluded]`. Read by `03-packages.sh` via `shared/read-packages`.

**There are no architecture sections.** Adding `[fedora_aarch64]` / `[excluded_aarch64]`
keyed on `uname -m` — mirroring the existing `_v44` version-suffix convention — is the
clean extension point, and is plausibly upstreamable.

Known x86-only entries: `grub2-efi-x64-cdboot` (aarch64 wants `grub2-efi-aa64-cdboot`),
and the Intel GPU stack in `[multimedia_overrides]` — `intel-gmmlib`, `intel-mediasdk`,
`intel-vpl-gpu-rt`, `libva-intel-media-driver`. The generic `mesa-*` entries in that
section are arch-neutral and worth keeping.

`03-packages.sh` itself contains **zero** arch conditionals.

### 5.3 Kernel swap pattern (`04-install-kernel-akmods.sh`)

The canonical bootc kernel replacement, reusable for any custom kernel:

```
rpm --erase kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra --nodeps
→ install replacement kernel RPMs
→ dnf5 versionlock add kernel kernel-core kernel-modules ...
→ dracut --no-hostonly --kver "${KERNEL}" --reproducible \
         --add "ostree dmsquash-live dmsquash-live-autooverlay"
→ chmod 0600 initramfs.img && touch .bluefin-initramfs-done
```

The `versionlock` step is load-bearing: without it a later rebase silently restores the
Fedora kernel. `dracut` needs an explicit `--kver` — it defaults to the *running* kernel
and will fail inside a container.

Not needed on arm64 (no akmods), but retained here for the parked Surface work.

## 6. `bootc-image-builder` output types

`qcow2` (default), `ami`, `vmdk`, `raw`, `vhd`, `gce`, `bootc-installer`, `anaconda-iso`,
`pxe-tar-xz`.

`--target-arch` cross-builds, but the arch must exist in the bootc-image-builder image
**and** the target bootc image. Requires rootful podman.

- **VMware Fusion** → `--type vmdk`
- **UTM / QEMU** → `--type qcow2`

## 7. CI runners

`ubuntu-24.04-arm` / `ubuntu-22.04-arm`: arm64 hosted runners, GA since Aug 2025, free on
public repos, and available in private repos since Jan 2026. 4 vCPU. Native arm64 — no
QEMU emulation in the build path.
