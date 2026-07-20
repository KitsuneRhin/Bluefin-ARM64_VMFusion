# Migration package — SurfaceBlue → arm64 Bluefin project

Contents of `Migration.zip`, extracted from the SurfaceBlue repo on 2026-07-20, for
starting the aarch64 Bluefin-for-Apple-Silicon project in a fresh repository.

Unzip into the new repo root. Nothing here is Surface-specific.

---

## What's in here

```
docs/ARM64-ROADMAP.md      The plan. Start here.
docs/BLUEFIN-REFERENCE.md  Verified upstream facts — digests, actions catalogue,
                           build pattern, package-manifest landmines.
Justfile                   Local build + VM recipes. Needs 2 edits, see below.
disk_config/disk.toml      Disk sizing for bootc-image-builder (20 GiB root).
.github/renovate.json5     Renovate config — generic, no dead references.
.github/dependabot.yml     GitHub Actions version updates.
LICENSE                    Apache 2.0.
.gitignore / .gitattributes
```

## Read order

1. `docs/ARM64-ROADMAP.md` — §0 feasibility, §1 known breakages, §3 phases
2. `docs/BLUEFIN-REFERENCE.md` — only when you need a specific fact

Phase 1 is already **done** (Silverblue aarch64 validated in VMware Fusion). Start at
Phase 2: vendor the subtree, apply the arm64 patches from §1, build locally.

---

## Required edits before use

### `Justfile` — two things

1. **Line 1** reads `export image_name := env("SurfaceBlue", "SurfaceBlue")`. That reads
   an env var literally named `SurfaceBlue`. Change to something like:
   `export image_name := env("IMAGE_NAME", "bluesilicon")`
2. **`build-iso` / `rebuild-iso` / `run-vm-iso` reference `disk_config/iso.toml`, which
   does not exist** — SurfaceBlue only ever had `iso-gnome.toml` and `iso-kde.toml`. This
   is a pre-existing latent break, carried over unfixed so you can decide. ISO isn't
   needed for the VM path; either point it at a real file or delete those three recipes.

Otherwise the Justfile is clean — no dead upstream references, and `build-qcow2`,
`run-vm-qcow2`, and `spawn-vm` already wrap `bootc-image-builder` correctly. For Fusion
you'll want a `build-vmdk` recipe alongside `build-qcow2`; the `_build-bib` helper already
takes the type as a parameter, so it's a one-line addition.

### `renovate.json5`

Generic as-is. Once the Containerfile exists, add rules to track the Silverblue arm64
base digest and the `projectbluefin/actions` SHAs.

---

## Deliberately left behind, and why

| File | Why not |
|---|---|
| `Containerfile` | Pinned to the dead `bluefin-dx-surface-nvidia-open:42` base. Start from `finpilot`. |
| `build_files/build.sh` | Old ublue template stub, 13 lines, nothing reusable. |
| `.github/workflows/build.yml` | Old ublue template. Rebuild from `projectbluefin/actions` — see reference §4. |
| `.github/workflows/sync.yml` | Superseded by git subtree (roadmap §2.1). |
| `scripts/sync-upstream.sh` | Points at `ublue-os/bluefin` (moved org) and subpath `pkgs/container/bluefin-dx`, which is a GHCR *package URL*, not a repo path — it could never have worked. Superseded by subtree. |
| `scripts/diff-report.sh` | Diff concept is good but wired to the rsync-vendoring model and calls `rpm-ostree db diff`, unavailable in CI. `git subtree pull` gives you real diffs for free. |
| `scripts/preflight.sh` | Asserts Surface-specific paths (`surface-kernel-install.service`, `linux-surface.repo`). |
| `scripts/smoke-test-surface.sh` | Surface hardware probing — `kernel-surface`, `iptsd`, evtest. |
| `disk_config/iso-gnome.toml`, `iso-kde.toml` | Kickstart points at `ghcr.io/ublue-os/image-template:latest`, dead. ISO out of scope. |
| `cosign.pub` | Old keypair. Roadmap §3 specifies **keyless OIDC** signing; generate fresh if you go key-based. |
| `artifacthub-repo.yml` | Contains the SurfaceBlue repo ID. Regenerate if you publish. |
| `README.md`, `upstream/`, `system_files/` | SurfaceBlue-specific. Stay put. |
| `docs/ROADMAP.md` | The Surface roadmap. Stays with SurfaceBlue — it's a different project, parked pending linux-surface kernel 7.x patches. |

---

## First actions in the new repo

```bash
git init && unzip Migration.zip
git subtree add --prefix=upstream \
    https://github.com/projectbluefin/bluefin main --squash
```

Then work Phase 2. The three known-broken things to patch are in roadmap §1 —
`grub2-efi-x64-cdboot`, the Intel entries in `[multimedia_overrides]`, and
`21-container-native-iso.sh`. Everything else is expected to build; find the rest empirically
rather than predicting it.

Make the repo **public** if you want free arm64 runners — they're free on public repos,
billable on private.
