# BlueSilicon — aarch64 Bluefin for Apple Silicon VMs

Target: a **Bluefin base** image for `linux/arm64`, built natively in CI, delivered as a
bootable disk image to run in **VMware Fusion** on an Apple Silicon Mac. No x86 emulation
anywhere in the build or the runtime. `dx` follows once base boots.

Decisions taken: vendor upstream `build_files`/`system_files` via **git subtree**; CI
publishes both the container **and** a downloadable disk image; **base first, dx second**.

Upstream Bluefin facts referenced throughout are recorded in
[BLUEFIN-REFERENCE.md](BLUEFIN-REFERENCE.md) — registry digests, the reusable actions
catalogue, and the upstream build pattern.

The Surface project (SurfaceBlue) is a separate concern, parked pending linux-surface
kernel 7.x patches. Its roadmap stays in that repository.

---

## 0. Feasibility — verified 2026-07-20

Every layer of the stack was checked against live registries, not assumed.

| Component | arm64 status | How verified |
|---|---|---|
| `quay.io/fedora-ostree-desktops/silverblue:44` | ✅ multi-arch index | OCI index lists `linux/amd64`, `linux/arm64` |
| `ghcr.io/projectbluefin/common:latest` | ✅ | index lists both |
| `ghcr.io/ublue-os/brew:latest` | ✅ | index lists both |
| COPR `ublue-os/packages` | ✅ | `fedora-44-aarch64` chroot present |
| COPR `ublue-os/staging` | ✅ | `fedora-44-aarch64` chroot present |
| negativo17 `multimedia/fedora-44/aarch64` | ✅ | 556 aarch64 RPMs |
| Tailscale | ✅ | `stable/fedora/aarch64/repodata/repomd.xml` → 200 |
| `bootc-image-builder` | ✅ | index lists arm64 |
| GitHub `ubuntu-24.04-arm` runners | ✅ | GA Aug 2025, free on public repos |
| `build_files/base/03-packages.sh` | ✅ | contains zero arch conditionals |

**The Homebrew layer was the main risk and it clears.** Homebrew upstream does not support
ARM64 Linux, but ublue publishes an arm64 `brew` image, so the layer composes.

### 0.1 The structural catch

`projectbluefin/bluefin:stable` and `bluefin-lts:stable` are both **amd64-only** (confirmed
via config blob `architecture: amd64`). There is no arm64 Bluefin to layer onto.

So unlike the Surface project — where we layer on a published Bluefin image and inherit
their maintenance — here we **run Bluefin's build ourselves** from Silverblue arm64. We
track their `build_files/`, not their image. When they restructure their build, we feel it.
That is the dominant ongoing cost of this project; size it honestly.

Encouraging signal: `common` and `brew` are already arm64 while Bluefin is not. Someone
upstream is laying arm64 groundwork on purpose. Upstreaming is a realistic endgame, and
§4 is written to keep that door open.

### 0.2 What gets *deleted* on arm64

`ghcr.io/ublue-os/akmods` is amd64-only. The entire kernel-swap step —
`04-install-kernel-akmods.sh`, the hairiest script in Bluefin's build — **does not run**.
We keep Fedora's stock aarch64 kernel.

Dropped with it: ZFS, v4l2loopback, NVIDIA, Secure Boot / MOK signing. All meaningless in
a Mac VM. The thing that made the Surface project expensive is simply absent here.

`19-initramfs.sh` still runs (ostree dracut config), but with no `--kver` juggling, since
we never replace the kernel.

---

## 1. Concrete arch landmines already identified

These are known-broken *before* the first build. Fix them in the arm64 patch set.

### 1.1 `build_files/packages/base.toml`

The manifest has sections for `[fedora]`, `[fedora_v42..44]`, `[excluded]`,
`[multimedia_overrides]` — but **no arch sections at all**. Confirmed offenders:

- **`grub2-efi-x64-cdboot`** — x86_64-only. aarch64 needs `grub2-efi-aa64-cdboot`.
  This is a hard build failure.
- **`[multimedia_overrides]`** is largely Intel GPU stack: `intel-gmmlib`,
  `intel-mediasdk`, `intel-vpl-gpu-rt`, `libva-intel-media-driver`. x86_64-only.
  The generic `mesa-*` entries in that section are fine on aarch64 and worth keeping.
- ~~**`igt-gpu-tools`** — verify aarch64 availability; drop if absent.~~
  **Resolved 2026-07-20: KEEP.** `igt-gpu-tools-2.2-2.fc44.aarch64` is present in the F44
  aarch64 repos. No change needed.

A full static screen of `[fedora]` + `[fedora_v44]` (62 packages) against the F44 aarch64
release *and* updates repos found **`grub2-efi-x64-cdboot` as the only genuine absence**.
`pipewire-libs-extra` also fails to resolve in Fedora, but it is absent on x86_64 too — it
comes from negativo17, where the aarch64 build does exist. Not an arch problem.

Likewise verified against negativo17's aarch64 repo: all `mesa-*`, `libva`, `libheif`,
`x264-libs`, `x265-libs` present; the four Intel packages absent. §1.1 was exactly right.

**Implemented fix (upstreamable):** `patches/0001-arch-aware-package-manifest.patch` adds
optional `[<section>_<arch>]` sections keyed off `$(uname -m)`, mirroring the existing
`_v44` version-suffix convention.

Note: **`read-packages` needed no change at all.** It already takes an arbitrary section
name and exits 1 on a missing one, and `03-packages.sh` already has the
`2>/dev/null || true` idiom for optional sections (used for `fedora_v${VERSION}`). The
patch reuses that idiom, so it touches only `03-packages.sh` and `base.toml` — a smaller
and more upstreamable diff than §1.1 originally anticipated.

### 1.1a `20-tests.sh` asserts the x86 bootloader — found 2026-07-20

Not previously identified. `20-tests.sh` has an `IMPORTANT_PACKAGES` list containing
`grub2-efi-x64-cdboot` and hard-exits if any entry is missing. Moving the package to an
arch section in `base.toml` is not enough — this assertion fails at the very end of
Stage 2, after the entire expensive build. Patched in `0001` via a `uname -m` case that
appends the correct payload for the arch.

### 1.1b Dropping akmods breaks `05-override-install.sh` — found 2026-07-20

Not previously identified, and a direct consequence of §0.2. `05-override-install.sh`
runs `rpm --erase --nodeps kernel-devel` unconditionally under `set -e`, but
`kernel-devel` is installed by `04-install-kernel-akmods.sh` — the very script we skip.
On aarch64 the package is absent and the erase fails, killing Stage 1.

Fixed in `patches/0002-tolerate-absent-kernel-devel.patch` by guarding the erase with an
`rpm -q` check. Worth offering upstream: the guard is correct on x86_64 too.

### 1.1c Build secret trips `bootc lint` `nonempty-run-tmp` — found in CI 2026-07-24

Not arch-related; surfaced only once the build ran in CI with a GITHUB_TOKEN secret.
Passing `--secret id=GITHUB_TOKEN` mounts it at `/run/secrets/GITHUB_TOKEN`. buildah keeps
`/run/secrets` mounted for **every** RUN of a secret-enabled build, so no layer can remove
it (`rm -rf /run/secrets` → `Device or resource busy`), and the empty `/run/secrets`
directory is committed into the image. `bootc container lint`'s `nonempty-run-tmp` check
flags it, and `--fatal-warnings` turns that into a build failure. Upstream's
`clean-stage.sh` tries to clear `/run`, but it runs inside Stage 2 with the secret still
mounted, so it cannot succeed either.

**Decision: build the base image unauthenticated** (no `--secret`). The token bought almost
nothing here — the only `ghcurl` GitHub fetch in the base path is a single
`raw.githubusercontent.com` request (the CoreOS sulogin generator); base/common/brew pulls
use registry auth, and the extension submodule clones are plain public git. This keeps the
image `/run` clean and the lint fully enforced (only `--skip nonempty-boot`, matching
upstream). If a future variant (dx, Phase 5) needs authenticated fetches, revisit with a
non-`/run` secret target or a post-build check exclusion — do **not** simply re-add
`--secret` without handling `/run/secrets`.

### 1.2 `21-container-native-iso.sh` — drop entirely

Fetches `ublue-os/akmods/certs/public_key.der` into `/etc/sb_pubkey.der` for Secure Boot,
and builds the Titanoboa live-ISO contract. Both are x86-oriented and irrelevant to a VM
image. Remove from the Containerfile.

### 1.3 Flatpaks

Flathub aarch64 coverage is per-app and thinner than x86_64. Bluefin preinstalls a set;
expect some to fail resolution. Detection is trivial (build fails), fix is trimming.
Budget one iteration cycle for this; do not try to predict it in advance.

### 1.4 GNOME extensions stage

`extension-builder` installs `glib2-devel meson sassc cmake dbus-devel` and compiles
schemas — all arch-neutral. Expected to work unchanged. Verify, don't pre-emptively patch.

---

## 2. Repository layout

New repo (suggested `bluesilicon`), **not** this one. SurfaceBlue stays parked and its
git history stays about Surface.

```
Containerfile                  # arm64, FROM silverblue:44 (digest-pinned, arm64)
upstream/                      # git subtree of projectbluefin/bluefin
  build_files/
  system_files/
  image-versions.yml
patches/                       # arm64 patch set applied over the subtree
  0001-arch-aware-package-manifest.patch
  0002-skip-akmods-on-aarch64.patch
  0003-drop-container-native-iso.patch
.github/workflows/
  build.yml                    # ubuntu-24.04-arm
  disk.yml                     # qcow2 via bootc-image-builder
  upstream-sync.yml            # subtree pull + drift PR
docs/
```

### 2.1 Subtree discipline

- `git subtree add --prefix=upstream https://github.com/projectbluefin/bluefin main --squash`
- `upstream-sync.yml` runs weekly: `git subtree pull`, reapply `patches/`, open a PR on
  change. **Never edit `upstream/` directly** — that is what makes drift legible and
  upstreaming possible.
- If a patch stops applying, the sync PR fails loudly. That is the intended alarm.

### 2.2 Submodule discipline (GNOME extensions)

Upstream carries its bundled GNOME Shell extensions as **git submodules** (9 of them,
under `system_files/shared/usr/share/gnome-shell/extensions/`). `git subtree add` vendors
the tree but **does not fetch submodule contents** — the directories land empty, and the
`extension-builder` stage fails at the first `glib-compile-schemas`. This is orthogonal to
arch; an amd64 subtree build hits it identically.

Handled without touching `upstream/`:
- `extensions.lock` records `path / url / sha / branch` for each submodule, with the SHA
  taken from the subtree's gitlink tree entries — so upstream's *exact* pins are reproduced.
- `scripts/prepare-context.sh` shallow-fetches each pinned SHA into `_build_ctx/` (cached
  by SHA under `_build_ext_cache/`).
- After every `git subtree pull`, run `scripts/gen-extensions-lock.sh` to regenerate the
  lock, then review the diff. **A changed SHA is an upstream extension bump** — the same
  legible-drift signal the patch set gives for build scripts. Fold this into
  `upstream-sync.yml` in Phase 3.

### 2.3 Tagging & versioning

Git tags mark checkpoints. Format:

```
BlueARM_<major.minor.patch>-<variant>-<arch>-<maturity>
```

- **version** — rolling semver (`0.1.0`, `0.4.56`, …). Iterative, bumped per meaningful
  checkpoint; not tied to a "full release" v1/v2 scheme.
- **variant** — `base` | `dx` | …
- **arch** — `arm64`.
- **maturity** — how publish-ready the checkpoint is:
  - `alpha` — builds and passes `bootc lint`, but **not boot-verified**. Not publishable.
  - `beta` — boots and runs in the target VM; under testing.
  - `release` — validated end-to-end; ready to publish.

Example: `BlueARM_0.1.0-base-arm64-alpha` (current checkpoint — base builds + lints; VMDK
builds in CI; boot in Fusion not yet confirmed). The container image tag (`DEFAULT_TAG`,
currently `alpha`) tracks the same maturity word.

### 2.4 Registry release streams

Git tags above are immutable checkpoints in history. The registry carries two *floating*
streams plus an immutable per-build tag:

| Tag | Meaning | Written by |
|---|---|---|
| `<short-sha>` | immutable, every build | every push to `dev` / `main` |
| `:testing` | newest `dev` build; may be broken | `build.yml`, **`dev` pushes only** |
| `:stable` | last build verified booting in a VM | `promote.yml`, manual dispatch |
| `:latest` | alias of `:stable`, for tooling that assumes it exists | `promote.yml`, manual dispatch |

A `main` push publishes its `<short-sha>` tag and the ISO artifact but moves no
floating stream. `main` lags `dev`, so writing `:testing` from it would drag the
stream backwards for anyone tracking it, and writing `:stable` from it would mean
"passed pr-check" rather than "confirmed booting".

**Promotion re-tags a verified digest — it never rebuilds.** A rebuild from the same commit
can drift (base image, upstream packages, COPR content), so the artifact tested would not be
the artifact shipped. Promotion is a registry-side copy of an existing digest:

```bash
skopeo copy --all \
  docker://ghcr.io/kitsunerhin/bluesilicon@sha256:<verified-digest> \
  docker://ghcr.io/kitsunerhin/bluesilicon:stable
```

Because the cosign signature is bound to the digest rather than the tag, re-tagging carries
the signature with it — a promoted image satisfies the Phase 6 `sigstoreSigned` policy with
no re-signing step.

Switching streams on an installed VM is a single `bootc switch`, so keeping the streams
distinct costs the user nothing.

**Implemented 2026-07-31.** `build.yml` writes `<short-sha>` always and `:testing` on `dev`
only; `promote.yml` (workflow_dispatch, takes a short SHA or digest) resolves the input to an
immutable digest, verifies it was cosign-signed by this pipeline, then copies it to `:stable`
and optionally `:latest`. Promotion is gated on provenance so `:stable` can never be moved
onto an image our build workflow did not sign.

---

## 3. Phases

### Phase 1 — Prove the runtime path — ✅ DONE

**Status: complete.** Stock Silverblue aarch64 confirmed running "smooth and functional"
in **VMware Fusion** on Apple Silicon (2026-07-20). The runtime target is validated, which
retires the single biggest non-build risk in this project before any code was written.

Consequence for the rest of the plan: the VM host is **VMware Fusion**, not UTM/QEMU. That
changes the delivery format — see Phase 4.

### Phase 2 — Minimum viable arm64 Bluefin base — ✅ DONE

**Status: complete 2026-07-24.** `localhost/bluesilicon:alpha` builds clean via
`podman build --platform linux/arm64` and passes `bootc container lint --fatal-warnings
--skip nonempty-boot` (12 passed, 2 skipped). 7.92 GB, `architecture: arm64`.

Verified inside the built image: `aarch64` throughout; `grub2-efi-aa64-cdboot` present and
x64 absent; stock Fedora `kernel-core-7.1.4-200.fc44.aarch64` with a generated 236 MB
initramfs (dracut ran in Stage 2, no kernel swap); no akmods, no kernel-devel;
`igt-gpu-tools` kept; Intel GPU stack absent; mesa sourced from negativo17; all 9 GNOME
extensions present and compiled.

What it took beyond the roadmap's three §1 fixes:
- Two extra landmines, both now patched — see §1.1a (`20-tests.sh` bootloader assertion)
  and §1.1b (`kernel-devel` erase). Each would have cost a full build cycle to discover.
- The GNOME extensions are upstream **git submodules** the subtree does not fetch. Handled
  via `extensions.lock` + a fetch step in `scripts/prepare-context.sh`. See §2.2.
- **No Flatpak failures surfaced.** The roadmap budgeted an iteration for aarch64 Flatpak
  gaps (§1.3); none occurred in the base image. `open-vm-tools` question (Phase 4) still open.

Build mechanics: `upstream/` is a pristine subtree; `scripts/prepare-context.sh` assembles
`_build_ctx/` from it plus `patches/` plus the fetched extensions; `just build` wraps this.

**Cache-split wrinkle to resolve in Phase 3.** Reference §5's two-stage split is preserved
structurally, but empirically a `system_files`-only change (e.g. an extension bump) busts
Stage 1's cache too: both stages bind-mount `from=ctx`, and the single `ctx` scratch stage
COPYs *both* `build_files` and `system_files`, so any `system_files` change rebuilds `ctx`
and invalidates Stage 1's package layer — the exact 20–80 min hit the split was meant to
avoid. Fix is to split `ctx` into `ctx-build` (build_files only) and `ctx-system`, and have
Stage 1 bind only `ctx-build`. Deferred: it's a CI-time optimization, and it deviates from
upstream's Containerfile so it needs weighing against subtree drift. Flagged, not yet done.

### Phase 3 — CI — ✅ DONE (push/sign/scan)

**First green CI build 2026-07-24** (`build.yml` on `ubuntu-24.04-arm`, native). The image
builds and passes `bootc container lint --fatal-warnings` (12 passed, 2 skipped) on a
hosted arm64 runner. One CI-only fix was needed — the build secret / `nonempty-run-tmp`
interaction in §1.1c.

**Runner disk — measured, not assumed. No job split needed.** The `ubuntu-24.04-arm`
runner has a **single 145 GB root disk (~109 GiB free fresh); there is no separate `/mnt`
volume** — `/mnt` is just a directory on `/`. So the "relocate podman storage to `/mnt`"
step moves data within the same filesystem and yields no space on this runner (kept anyway:
harmless, and correct if GitHub ever adds a scratch disk). The reclaim step is what pays —
`free-disk-space` took free space from 109 → 123 GiB. After a full image build (7.93 GB
image, 8.9 GB podman store) **113 GiB remained free**. A `bootc-image-builder` VMDK plus
`rechunk` fits in one job with enormous margin, so Phase 4's disk build can share the runner
— splitting `disk.yml` out remains a clean-separation choice, not a space necessity.

`.github/actions/prepare-disk` (reclaim → report) and the instrumented `build.yml`
implement this.

**Phase 3 complete 2026-07-26.** `build.yml` now: logs in to GHCR → pushes with an
immutable SHA tag + a floating branch tag (`latest` on main, `dev` on dev) → signs with
keyless cosign (OIDC, `sigstore/cosign-installer@v4.1.2`) → scans with Trivy
(`aquasecurity/trivy-action@v0.36.0`, `continue-on-error: true`, informational for now) →
builds and uploads the Anaconda ISO artifact. `build.yml` now triggers on both `main` and
`dev`. Once installed, the VM can update in-place via `sudo bootc upgrade` against
`ghcr.io/kitsunerhin/bluesilicon:latest`. The `projectbluefin/actions` composition
(`rechunk`, `scan-image`) is deferred — the custom pipeline covers the same ground.

#### Original Phase 3 plan

`build.yml` on `ubuntu-24.04-arm` (native, no emulation). Compose from
`projectbluefin/actions` — the same set catalogued in [ROADMAP.md](ROADMAP.md) §0.6:
`setup-runner` → `dnf-cache` → build → `generate-tags` → `push-image` → `rechunk` →
`sign-and-publish` (keyless OIDC) → `scan-image`. Pin each action to a commit SHA.

Note: those actions are written for amd64 Bluefin. Expect at least one to need an arm64
accommodation — `rechunk` and `scan-image` are the likely candidates. Verify each rather
than assuming drop-in.

Publish to `ghcr.io/kitsunerhin/bluesilicon:stable`. Single-arch manifest is fine;
`create-manifest` is only needed if amd64 is ever added.

### Phase 4 — Disk image delivery (VMware Fusion) — ✅ DONE (pending `dev → main` merge)

**CI produces a VMDK 2026-07-24.** The `build.yml` job (on `dev`) builds the image, bridges
it into rootful storage, runs `bootc-image-builder --type vmdk --rootfs btrfs` against
`disk_config/disk.toml`, and uploads a `zstd`-compressed artifact + `sha256` as a 14-day
Actions artifact. First green disk build: `bluesilicon-alpha-<sha>.aarch64.vmdk.zst`, ~3.8 GiB
(3.78 GiB used of the 20 GiB sparse disk). No registry push / signing / Release yet — those
wait until the runtime path is confirmed. Native arm64 build, so no `--target-arch` needed.

Three things learned building it:
- **Do not relocate podman storage.** `ubuntu-24.04-arm` has a single root disk (`/mnt` is a
  directory on it, not a separate volume), so a move frees nothing — and relocating rootful
  storage baked the `/mnt` path into the libpod DB, which then mismatched bib's default
  `/var/lib/containers` mount (`database configuration mismatch`). Default paths only.
- **`open-vm-tools` + `open-vm-tools-desktop` are already installed and `vmtoolsd` is
  enabled** in the base image (Silverblue default), so the §4 "pleasant to use" gap needs no
  manifest change. Clipboard/display integration should work on first boot.
- **zstd compresses this disk by only ~1.3%** (content is already dense), so the workflow uses a
  low level (`-3`) — high levels waste CPU for no size gain.

**VMDK boot failed 2026-07-26.** VMware Fusion on Apple Silicon rejected the bib-produced
VMDK as "target image not recognized" and would not boot it. Root cause: bib emits a
**stream-optimized VMDK** (VMware's transfer/archive format), which Fusion does not treat as
a directly bootable disk. Fusion expected a flat or sparse monolithic VMDK. Additionally,
the Fusion NVMe controller assignment did not match the image's EFI boot entries.

**Pivot to Anaconda ISO (2026-07-26).** `--type anaconda-iso` produces a bootable Anaconda
installer that matches the workflow already known to work (Fedora Silverblue ISO boots in
Fusion instantly). Boot flow: mount ISO → install to a fresh virtual disk → reboot into
installed system. Once the ISO path validates end-to-end, revisit flat-VMDK via
`qemu-img convert -f raw -O vmdk -o subformat=monolithicFlat` or `bootc upgrade`-based
update distribution. Artifact filename switches from `.vmdk.zst` to `.iso.zst`.

**ISO boots and installs successfully — 2026-07-26.** Anaconda ISO boots under Fusion on
Apple Silicon (UEFI + NVMe). Deployment phase at `/run/install/repo/container` takes
15–40 min with no visible progress bar (silent OCI layer unpack onto the virtual disk);
this is expected. After reboot, initial GNOME setup ran normally. Full ARM64 boot chain
confirmed. Tagged `BlueARM_0.1.0-base-arm64-beta`.

**Delivery complete 2026-07-31.** `docs/VM-SETUP.md` is written, the Phase 3 remainder
(push/sign/scan) shipped, and §5.1 fixed the ISO stamping an unusable update source. The ISO
path is the supported install route; flat-VMDK via `qemu-img convert` remains an unexplored
option, but `bootc upgrade` from the registry has made it unnecessary in practice.

Outstanding for this phase: **merge `dev` → `main`**, which has not happened since the
tagging rework — `main` still carries the old `:dev`/`:latest` behaviour.

### Phase 5 — dx variant

Second matrix leg once base is stable. `dx` pulls in devcontainer tooling, docker/podman,
VS Code — more COPR and Flatpak surface, so more aarch64 gaps. Deliberately sequenced last.

**Scope reduced 2026-07-31.** The dx *Flatpak* set already ships in the base image — the
`preinstall.d` generation in `patches/0003` consumes both `system-flatpaks.Brewfile` and
`system-dx-flatpaks.Brewfile`. Folding six packages in was cheaper than carrying a second
image variant through the build matrix. What remains for a real `dx` leg is the RPM/COPR
surface (VS Code, devcontainer CLI, docker), not the Flatpaks.

#### 5.1 Installed VM points at the wrong update source — found 2026-07-30, fixed 2026-07-31

bootc-image-builder stamps the deployment with whatever reference it composed *from*. CI
composes from the local build tag, so an installed VM reports `localhost/bluesilicon:alpha`
as its upstream and `bootc upgrade` cannot resolve it. The one-time workaround is
`bootc switch ghcr.io/kitsunerhin/bluesilicon:<stream>`, which rewrites the recorded source
permanently — but a freshly installed ISO should never need it.

**Resolution.** bootc-image-builder documents no `--target-imgref` and no `--local` flag, so
overriding the recorded reference at install time was not available. Instead the image is
re-tagged under its registry reference in rootful storage before bib runs, and bib is invoked
against that reference:

```bash
sudo podman tag "localhost/${IMAGE_NAME}:${DEFAULT_TAG}" "${INSTALL_REF}"
```

Because the rootful store is already bind-mounted into the bib container, this resolves
locally and costs no extra pull. The stamped reference follows the stream that produced the
ISO (§2.4): a `dev` build stamps `:testing`, a `main` build stamps `:stable`.

**Corrected 2026-08-03.** `main` initially stamped its immutable `<short-sha>` tag, on the
reasoning that main publishes no floating stream. That resolves correctly and looks right in
`bootc status`, but the tag never moves — so `bootc upgrade` on a VM installed from a release
ISO would report no update, permanently. That is the very failure this section exists to fix,
wearing a convincing disguise. Release ISOs stamp `:stable`. The ISO's contents and whatever
`:stable` points to at install time may differ; the first upgrade reconciles them, which is
the intended behaviour.

Landed together with the `:dev` → `:testing` rename, since both touch the same tagging logic.

**Not yet verified on hardware:** that a VM installed from a post-fix ISO reports the registry
reference in `bootc status` and can `bootc upgrade` with no `bootc switch` first. Confirm on
the next clean install.

#### 5.2 Vulnerability gating — implemented 2026-07-31

Trivy runs twice in `build.yml`: an informational pass reporting CRITICAL+HIGH that never
fails, and a gate pass that fails the build on **CRITICAL only**. HIGH and below are visible
but non-blocking, on the grounds that this image inherits a large Go-binary surface from
upstream and blocking on HIGH would stall work we cannot action.

Suppressions live in `.trivyignore`, and are only legitimate for findings that cannot be
fixed in this repository — a vendored dependency inside a prebuilt upstream binary. Each
entry carries a reason, a date, and its removal condition. The list is currently one entry
(`CVE-2026-33186`, grpc in an upstream Go binary) and should be reviewed whenever the
informational pass changes.

### Phase 6 — Signature enforcement (pre-release gate)

Before promoting any build to `release` maturity, configure the installed image to
**reject unsigned pulls** from our registry. Currently we sign every push (keyless cosign
via OIDC) but the system's `/etc/containers/policy.json` is Fedora's default, which does
not require it.

What this involves (all in `system_files/`, no CI changes needed):

- `/etc/containers/policy.json` — add a `sigstoreSigned` rule scoped to
  `ghcr.io/kitsunerhin/bluesilicon` with the Fulcio issuer
  (`https://token.actions.githubusercontent.com`) and the workflow subject
  (`https://github.com/KitsuneRhin/Bluefin-ARM64_VMFusion/.github/workflows/build.yml@refs/heads/main`).
- `/etc/pki/sigstore/fulcio_root.crt` and `rekor.pub` — Sigstore root trust bundle.
- `/etc/containers/registries.d/ghcr-kitsunerhin.yaml` — point at the cosign signature store.

Once in place, `bootc upgrade` will refuse to deploy any image that wasn't signed by our
GitHub Actions pipeline — closing the loop between §3 signing and actual enforcement.

To manually verify a push before enforcement is in place:
```bash
cosign verify \
  --certificate-identity-regexp="github.com/KitsuneRhin/Bluefin-ARM64_VMFusion" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  ghcr.io/kitsunerhin/bluesilicon:latest
```

### Phase 7 — Upstream (optional, high value)

The `[fedora_aarch64]` manifest patch from §1.1 is genuinely useful to Bluefin
independently of this project. Offer it upstream. If accepted, our patch set shrinks and
the subtree drift problem gets structurally smaller.

---

## 4. Risk register

| Risk | Severity | Mitigation |
|---|---|---|
| Upstream restructures `build_files/` | **High** | Subtree + patch set; weekly sync PR fails loudly rather than silently drifting |
| Upstream bumps/adds extension submodules | Medium | `gen-extensions-lock.sh` after each sync; SHA diff is the signal (§2.2) |
| ~~Flatpak aarch64 gaps~~ | ~~Medium~~ | **Retired for base** — no Flatpak failures in the base build (2026-07-24). Re-open for `dx` (Phase 5). |
| Extension bump triggers full package rebuild in CI | Low | Cache-split wrinkle, see Phase 3 note; split `ctx` scratch stage to fix |
| `projectbluefin/actions` assume amd64 | Medium | Verify each action on arm64 in Phase 3; `rechunk`/`scan-image` most suspect |
| negativo17 Intel-stack overrides | Medium | Already identified §1.1; keep generic mesa, drop Intel-specific |
| ~~VM graphics performance~~ | ~~Medium~~ | **Retired** — Fusion + Silverblue aarch64 validated 2026-07-20 |
| Fusion guest integration (clipboard/resize) | Low | Check `open-vm-tools` presence; add to manifest if missing |
| aarch64 package absent from Fedora | Low | Caught at build; add to `[excluded_aarch64]` |
| Release storage for disk images | Low | zstd compression; prune old releases |

---

## 5. Why this is the cheaper project

Against the Surface roadmap, on the same stack:

- No kernel building, no patch rebasing, no MOK enrollment, no Secure Boot chain
- No blocking upstream dependency — every component already ships arm64 **today**
- Native CI builds, free runners, no emulation
- Failure modes are build-time and loud, not boot-time and silent

The single genuine cost is subtree drift against a fast-moving upstream. Everything else
is assembly of parts that already exist.
