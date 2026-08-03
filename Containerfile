# aarch64 Bluefin base image for Apple Silicon VMs.
#
# Derived from projectbluefin/bluefin's Containerfile (vendored under upstream/).
# Build context is _build_ctx/, produced by scripts/prepare-context.sh, which
# copies the pristine subtree and applies patches/.
#
# Deltas from upstream, all arm64-driven:
#   * base image pinned to the arm64 child manifest of Silverblue 44
#   * 04-install-kernel-akmods.sh is NOT run — ghcr.io/ublue-os/akmods is
#     amd64-only. We keep Fedora's stock aarch64 kernel, so no kernel swap,
#     no versionlock, no MOK/Secure Boot chain. (roadmap §0.2)
#   * 21-container-native-iso.sh is NOT run — Secure Boot key fetch plus the
#     Titanoboa live-ISO contract, both x86-oriented and irrelevant to a VM
#     image. (roadmap §1.2)
#
# Upstream's two-stage cache split is preserved: stage 1 mounts only
# build_files/, stage 2 only system_files/. A system_files-only change keeps the
# stage 1 cache hit. (reference §5)

ARG BASE_IMAGE_NAME="silverblue"
ARG FEDORA_MAJOR_VERSION="44"
ARG BASE_IMAGE="quay.io/fedora-ostree-desktops/silverblue"

# arm64 child manifest digests, all verified live 2026-07-27.
#
# These are per-arch child digests, not multi-arch index digests, so the arch is
# explicit and does not depend on podman's platform resolution. Note that
# upstream's image-versions.yml pins `common` to its *amd64* child manifest —
# that pin is unusable here and must not be copied over.
ARG BASE_IMAGE_REF="${BASE_IMAGE}@sha256:a3cbab99847fa302d881100d2e7da1be2183ad7577f68250b999725054fe63f3"
ARG COMMON_IMAGE_REF="ghcr.io/projectbluefin/common@sha256:497cb90e7d30e1a93fda67c112b3146fb43e5e64a774301d2d7025cb57d1e90a"
ARG BREW_IMAGE_REF="ghcr.io/ublue-os/brew@sha256:8157460c2d2559ab7e5f2f6644a9c2be3b25fdf8d4a9fd42a34f6a0795eb359e"

# hadolint ignore=DL3006
FROM ${COMMON_IMAGE_REF} AS common
# hadolint ignore=DL3006
FROM ${BREW_IMAGE_REF} AS brew

FROM scratch AS ctx
COPY /system_files /system_files
COPY /build_files /build_files
COPY /image-versions.yml /image-versions.yml
COPY --from=common /system_files/shared /system_files/shared
COPY --from=common /system_files/bluefin /system_files/shared
COPY --from=brew /system_files /system_files/shared

# hadolint ignore=DL3006
FROM ${BASE_IMAGE_REF} AS base-common

ARG BASE_IMAGE_NAME="silverblue"
ARG FEDORA_MAJOR_VERSION="44"
ARG IMAGE_NAME="bluesilicon"
ARG IMAGE_VENDOR="kitsunerhin"
ARG UBLUE_IMAGE_TAG="stable"
ARG IMAGE_FLAVOR=""

# Stage 1 — package installs only (cache key: build_files/).
# Upstream runs 03 -> 04 -> 05 here; 04 is dropped on aarch64. 05 is patched to
# tolerate kernel-devel being absent, since 04 was what installed it.
RUN --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=cache,dst=/var/cache/rpm-ostree \
    --mount=type=bind,from=ctx,source=/build_files,target=/ctx/build_files \
    --mount=type=bind,from=ctx,source=/image-versions.yml,target=/ctx/image-versions.yml \
    --mount=type=secret,id=GITHUB_TOKEN \
    --mount=type=tmpfs,dst=/boot \
    bash -euo pipefail -c ' \
        dnf5 config-manager setopt keepcache=1 && \
        dnf5 config-manager setopt install_weak_deps=0 && \
        dnf5 -y swap fedora-logos generic-logos && \
        rpm --erase --nodeps --nodb generic-logos && \
        mkdir -p /tmp/scripts/helpers && \
        install -Dm0755 /ctx/build_files/shared/utils/ghcurl /tmp/scripts/helpers/ghcurl && \
        export PATH="/tmp/scripts/helpers:$PATH" && \
        /ctx/build_files/base/03-packages.sh && \
        /ctx/build_files/base/05-override-install.sh \
    '

# hadolint ignore=DL3006
FROM base-common AS extension-builder

RUN --mount=type=cache,dst=/var/cache/libdnf5 \
    bash -euo pipefail -c ' \
        dnf5 -y install glib2-devel meson sassc cmake dbus-devel \
    '

RUN --mount=type=bind,from=ctx,source=/system_files/shared/usr/share/gnome-shell/extensions,target=/ctx/extensions \
    --mount=type=bind,from=ctx,source=/build_files/shared/build-gnome-extensions.sh,target=/ctx/build_files/shared/build-gnome-extensions.sh \
    bash -euo pipefail -c ' \
        mkdir -p /usr/share/gnome-shell/extensions && \
        rsync -rvK /ctx/extensions/ /usr/share/gnome-shell/extensions/ && \
        bash /ctx/build_files/shared/build-gnome-extensions.sh \
    '

FROM base-common AS base

ARG BASE_IMAGE_NAME="silverblue"
ARG FEDORA_MAJOR_VERSION="44"
ARG IMAGE_NAME="bluesilicon"
ARG IMAGE_VENDOR="kitsunerhin"
ARG UBLUE_IMAGE_TAG="stable"
ARG IMAGE_FLAVOR=""
ARG SHA_HEAD_SHORT="dedbeef"
ARG VERSION=""

COPY --from=extension-builder /usr/share/gnome-shell/extensions /usr/share/gnome-shell/extensions
COPY --from=extension-builder /usr/share/glib-2.0/schemas /usr/share/glib-2.0/schemas

# Stage 2 — overlay system_files, finalize extensions, clean up.
# 19-initramfs.sh runs dracut here: upstream skips it when 04 left a marker, and
# since 04 never runs on aarch64 the marker is absent and dracut runs as intended.
RUN --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=bind,from=ctx,source=/system_files,target=/ctx/system_files \
    --mount=type=bind,from=ctx,source=/build_files/shared,target=/ctx/build_files/shared \
    --mount=type=bind,from=ctx,source=/build_files/base/00-image-info.sh,target=/ctx/build_files/base/00-image-info.sh \
    --mount=type=bind,from=ctx,source=/build_files/base/17-cleanup.sh,target=/ctx/build_files/base/17-cleanup.sh \
    --mount=type=bind,from=ctx,source=/build_files/base/18-workarounds.sh,target=/ctx/build_files/base/18-workarounds.sh \
    --mount=type=bind,from=ctx,source=/build_files/base/19-initramfs.sh,target=/ctx/build_files/base/19-initramfs.sh \
    --mount=type=bind,from=ctx,source=/build_files/base/20-tests.sh,target=/ctx/build_files/base/20-tests.sh \
    --mount=type=secret,id=GITHUB_TOKEN \
    --mount=type=tmpfs,dst=/boot \
    bash -euo pipefail -c ' \
        rsync -rvK --exclude="/usr/share/gnome-shell/extensions/***" /ctx/system_files/shared/ / && \
        mkdir -p /tmp/scripts/helpers && \
        install -Dm0755 /ctx/build_files/shared/utils/ghcurl /tmp/scripts/helpers/ghcurl && \
        export PATH="/tmp/scripts/helpers:$PATH" && \
        /ctx/build_files/base/00-image-info.sh && \
        bash /ctx/build_files/shared/finalize-gnome-extensions.sh && \
        /ctx/build_files/base/17-cleanup.sh && \
        /ctx/build_files/base/18-workarounds.sh && \
        /ctx/build_files/base/19-initramfs.sh && \
        /ctx/build_files/shared/validate-repos.sh && \
        /ctx/build_files/shared/clean-stage.sh && \
        /ctx/build_files/base/20-tests.sh \
    '

# Makes `/opt` writeable by default
RUN rm -rf /opt && ln -s /var/opt /opt

# /root is a symlink to /var/roothome, and /var is runtime state rather than part
# of the ostree commit — so this directory cannot be baked into the image and has
# to be recreated at boot. libsetup.sh's version-script opens
# $HOME/.local/share/ublue/setup_versioning.json.lock through a redirect that the
# shell sets up *before* the mkdir inside the same subshell runs; without the
# directory, ublue-system-setup.service exits 0 having skipped every privileged
# hook. The user-account equivalent is seeded via /etc/skel in 17-cleanup.sh.
# Parents are declared explicitly rather than relying on implicit creation.
RUN printf '%s\n' \
    'd /var/roothome/.local 0700 root root -' \
    'd /var/roothome/.local/share 0700 root root -' \
    'd /var/roothome/.local/share/ublue 0700 root root -' \
    > /usr/lib/tmpfiles.d/ublue-os-state.conf

CMD ["/sbin/init"]

RUN bootc container lint --fatal-warnings --skip nonempty-boot
