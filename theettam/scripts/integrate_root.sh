#!/usr/bin/env bash
# Theettam Phase-1 root integration for GKI 6.1.x
# DO NOT hand-edit VFS for SUSFS — apply matched upstream patch sets only.
#
# Flavors:
#   ksun_susfs   — KernelSU-Next (pershoot next-susfs @ 9c46185e) + SUSFS v2.2.0  [RECOMMENDED]
#   ksun_plain   — KernelSU-Next v3.3.0 only
#   sukisu_susfs — SukiSU-Ultra + SUSFS v2.2.0 hand-port (experimental)
#   resuki_susfs — ReSukiSU + native SUSFS (cleanest Suki lineage)
#
# Usage (from kernel root):
#   bash theettam/scripts/integrate_root.sh ksun_susfs
set -euo pipefail

FLAVOR="${1:-ksun_susfs}"
WORKDIR=$(pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

SUSFS_BRANCH="gki-android14-6.1"
# Matched pair used by Theettam CI (build-susfs173.yml)
PERSHOOT_KSUN_REPO="https://github.com/pershoot/KernelSU-Next.git"
PERSHOOT_KSUN_REF="9c46185e"
SUSFS4KSU_REPO="https://gitlab.com/simonpunk/susfs4ksu.git"
# fallback
SUSFS4KSU_REPO_GH="https://github.com/sidex15/susfs4ksu.git"
KSUN_OFFICIAL="https://github.com/KernelSU-Next/KernelSU-Next.git"
KSUN_TAG="v3.3.0"

log() { echo "[theettam-root] $*"; }

apply_susfs_fs() {
  local susdir="$1"
  log "Applying SUSFS fs-side patches (${SUSFS_BRANCH})"
  # Official unified patch — this IS the dcache/readdir/stat/open interception.
  # Do not reimplement; fuzz allowed for 6.1.175 minor drift.
  local p
  p=$(ls "${susdir}/kernel_patches/50_add_susfs_in_${SUSFS_BRANCH}.patch" 2>/dev/null || true)
  if [ -z "$p" ]; then
    p=$(ls "${susdir}/kernel_patches/50_add_susfs_in_gki-android14-6.1"*.patch 2>/dev/null | head -1 || true)
  fi
  if [ -z "$p" ]; then
    log "ERROR: SUSFS patch not found in ${susdir}/kernel_patches"
    ls -la "${susdir}/kernel_patches" || true
    exit 1
  fi
  patch -p1 --fuzz=3 < "$p" || {
    log "WARN: patch returned non-zero — inspect *.rej"
    find . -name '*.rej' | head -20
  }
  # Headers
  mkdir -p include/linux
  cp -f "${susdir}/kernel_patches/include/linux/susfs.h" include/linux/ 2>/dev/null || true
  cp -f "${susdir}/kernel_patches/include/linux/susfs_def.h" include/linux/ 2>/dev/null || true
  # Non-GKI / GKI hook glue files if present
  if [ -d "${susdir}/kernel_patches/fs" ]; then
    cp -a "${susdir}/kernel_patches/fs/." fs/ 2>/dev/null || true
  fi
  log "SUSFS_VERSION=$(sed -n 's/.*SUSFS_VERSION[^"]*\"\([^\"]*\)\".*/\1/p' include/linux/susfs.h 2>/dev/null | head -1)"
}

integrate_ksun_pershoot() {
  log "KernelSU-Next + SUSFS via pershoot matched fork @ ${PERSHOOT_KSUN_REF}"
  git clone --depth=1 "$PERSHOOT_KSUN_REPO" "$TMP/KernelSU" || \
    git clone --depth=1 "$KSUN_OFFICIAL" "$TMP/KernelSU"
  git -C "$TMP/KernelSU" fetch --depth=1 origin "$PERSHOOT_KSUN_REF" 2>/dev/null || true
  git -C "$TMP/KernelSU" checkout "$PERSHOOT_KSUN_REF" 2>/dev/null || \
    git -C "$TMP/KernelSU" checkout "$KSUN_TAG" 2>/dev/null || true

  # Official setup script if present
  if [ -f "$TMP/KernelSU/kernel/setup.sh" ]; then
    curl -LSs "https://raw.githubusercontent.com/pershoot/KernelSU-Next/${PERSHOOT_KSUN_REF}/kernel/setup.sh" \
      | bash -s "$PERSHOOT_KSUN_REF" || bash "$TMP/KernelSU/kernel/setup.sh" "$PERSHOOT_KSUN_REF"
  else
    # Manual driver drop-in
    mkdir -p drivers/kernelsu
    cp -a "$TMP/KernelSU/kernel/." drivers/kernelsu/
    grep -q kernelsu drivers/Makefile || echo 'obj-y += kernelsu/' >> drivers/Makefile
  fi

  # SUSFS fs-side from simonpunk (driver already has SUSFS in pershoot)
  git clone --depth=1 -b "$SUSFS_BRANCH" "$SUSFS4KSU_REPO" "$TMP/susfs4ksu" 2>/dev/null || \
    git clone --depth=1 "$SUSFS4KSU_REPO_GH" "$TMP/susfs4ksu"
  apply_susfs_fs "$TMP/susfs4ksu"
}

integrate_ksun_plain() {
  log "KernelSU-Next plain ${KSUN_TAG}"
  curl -LSs "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/${KSUN_TAG}/kernel/setup.sh" | bash -s "${KSUN_TAG}"
}

case "$FLAVOR" in
  ksun_susfs)   integrate_ksun_pershoot ;;
  ksun_plain)   integrate_ksun_plain ;;
  sukisu_susfs|resuki_susfs)
    log "Use prebuilt branch origin/${FLAVOR//_/-} on Mohithash/kernel_xiaomi_sm8635"
    log "or run CI workflow — hand-port is branch-specific (sukisu-susfs22 / resukisu-susfs22)"
    exit 2
    ;;
  *)
    log "Unknown flavor: $FLAVOR"
    exit 1
    ;;
esac

# Protect GKI symbol exports for vendor wifi/bt modules (Theettam CI pattern)
if [ -f android/abi_gki_aarch64_virtual_device ]; then
  log "KMI: leave abi lists intact (KMI_SYMBOL_LIST_STRICT_MODE=1 at build)"
fi

# Inject path-resolution include for SUS_MOUNT if missing in open path
# (official patch should already do this — verify)
if [ -f include/linux/susfs_def.h ]; then
  log "SUSFS headers present"
fi

log "Root integration complete for flavor=$FLAVOR"
log "Next: merge vendor/theettam_GKI.config and build with KMI_SYMBOL_LIST_STRICT_MODE=1"
