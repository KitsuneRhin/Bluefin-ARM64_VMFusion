# VM Setup — BlueSilicon on VMware Fusion (Apple Silicon)

Install the ARM64 Bluefin base image in VMware Fusion on an Apple Silicon Mac.
Once installed you can keep the VM current via `bootc upgrade` without reinstalling.

---

## Requirements

| | Minimum |
|---|---|
| Host | Apple Silicon Mac (M1 or later) |
| VMware Fusion | 13.x or later |
| vCPU | 4 |
| RAM | 8 GB |
| Disk | 20 GiB (the image uses btrfs; allocate more if you want headroom) |

---

## First install (ISO)

### 1. Get the ISO

Download the latest `bluesilicon-iso` artifact from the [Actions tab](../../../actions) on the
`main` branch. It's a `.iso.zst` file alongside a `.sha256`.

Verify and decompress:

```bash
sha256sum -c bluesilicon-alpha-<sha>.aarch64.iso.zst.sha256
zstd -d bluesilicon-alpha-<sha>.aarch64.iso.zst
```

### 2. Create the VM

1. **File → New → Create a custom virtual machine**
2. Operating system: **Other Linux 6.x kernel 64-bit ARM**
3. Firmware: **UEFI** (Fusion sets this automatically for ARM)
4. Create a new virtual disk — **20 GiB or larger**
5. Finish — do not start the VM yet

### 3. Mount the ISO and boot

1. Open VM Settings → **CD/DVD** → Connect to the `.iso` you decompressed
2. Check **Connect at power on**
3. Power on the VM — it will boot the Anaconda installer

### 4. Install

The Anaconda installer starts automatically with a pre-configured layout
(no interactive disk partitioning needed — the btrfs layout is baked in).

**The deployment phase is slow and silent.** When the progress bar reaches
"Deployment starting: /run/install/repo/container" it is unpacking the full
OCI image (~8 GB) onto the virtual disk. There is no per-layer progress
indicator. Expect **15–40 minutes** at this stage depending on your Mac's
storage. CPU and disk activity in Fusion's status bar confirm it's working.

When the installer finishes it reboots automatically into the installed system.

### 5. Initial setup

Complete GNOME's first-run setup (locale, keyboard, user account). After that
the system is fully functional.

---

## Release streams

| Tag | What it is |
|---|---|
| `:stable` | Last build booted and verified by a human. **Use this** unless you want the bleeding edge. |
| `:latest` | Rolling. Rebuilt automatically whenever upstream Bluefin or a base image moves. Untested. |
| `<short-sha>` | Immutable, one per build. Use to pin an exact image. |

`:latest` tracks upstream continuously and can break without warning — that is
what it is for. `:stable` only moves when a specific image has been booted and
promoted deliberately, so it is the safe default and the fallback to roll back to.

Installing from an ISO gives you `:stable`.

## Updating (after first install)

The ISO stamps its own stream as the update source, so this works with no
setup. In the running VM:

```bash
# Apply the newest image on the current stream and stage it for next boot
sudo bootc upgrade

# Reboot into the new deployment
systemctl reboot
```

`bootc upgrade` checks the registry, pulls only changed layers, and stages the
new deployment atomically — if anything goes wrong, roll back with
`sudo bootc rollback`.

To move between streams:

```bash
sudo bootc switch ghcr.io/kitsunerhin/bluesilicon:stable
```

Switching rewrites the recorded update source permanently, so subsequent
`bootc upgrade` calls follow the new stream. To pin an exact build instead, use
its digest:

```bash
sudo bootc switch ghcr.io/kitsunerhin/bluesilicon@sha256:<digest>
```

Check which image a VM is actually running with `sudo bootc status`.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| Installer hangs >45 min with no disk activity | Power off; check VM has ≥8 GB RAM and ≥20 GiB disk |
| GRUB prompt or no boot after install | In VM settings, verify firmware is set to UEFI |
| Black screen after GNOME login | Increase vRAM in Display settings (default 256 MB is usually fine) |
| `bootc upgrade` says "already up to date" | The registry image matches the installed deployment — nothing to do |
