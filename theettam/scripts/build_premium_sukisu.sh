#!/bin/bash
# Build Theettam Premium: SukiSU-Ultra + KPM + SUSFS v2.2.0 + DroidSpaces
# + Category A fragments. Hard Module.symvers gate vs baseline.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
export ARCH=arm64
export LLVM=1 LLVM_IAS=1
export KCFLAGS="${KCFLAGS:--Wno-error=array-bounds}"
export KBUILD_SYMTYPES=1
export PATH="${THEETTAM_CLANG:-$HOME/clang}/bin:${PATH}"
JOBS="${JOBS:-$(nproc)}"
OUT_BASE="${OUT_BASE:-out-premium-base}"
OUT="${OUT:-out-premium}"
STAMP_DIR="${STAMP_DIR:-dist/kabi}"
mkdir -p "$STAMP_DIR" dist logs

log(){ echo "[$(date -u +%H:%M:%S)] $*"; }

# Call/IMS isolation: DroidSpaces (USER_NS/PID_NS/SYSVIPC/...) is the main premium-only
# surface vs Theettam 2.1 SukiSU. Default OFF until VoLTE confirmed. Set SKIP_DROIDSPACES=0 to enable.
SKIP_DROIDSPACES="${SKIP_DROIDSPACES:-1}"

# CI: disable BTF — runners often fail pahole/BTF on vmlinux
disable_btf() {
  local cfg="$1"
  ./scripts/config --file "$cfg" --disable CONFIG_DEBUG_INFO_BTF || true
  ./scripts/config --file "$cfg" --disable CONFIG_DEBUG_INFO_BTF_MODULES || true
}


# --- pins (BOOT-NOTES / proven) ---
SUKISU_REPO="${SUKISU_REPO:-https://github.com/SukiSU-Ultra/SukiSU-Ultra}"
SUKISU_REF="${SUKISU_REF:-susfs_new}"
SUKISU_PIN="${SUKISU_PIN:-278d822a}"
SUSFS_REPO="${SUSFS_REPO:-https://gitlab.com/simonpunk/susfs4ksu.git}"
SUSFS_BRANCH="${SUSFS_BRANCH:-gki-android14-6.1}"
SUSFS_PIN="${SUSFS_PIN:-8199bb65}"

############################################
# Phase 0: baseline Image + Module.symvers (unmodified tree config)
############################################
if [[ "${SKIP_BASELINE:-0}" != "1" ]]; then
  log "=== BASELINE build (stock gki_defconfig path, no premium) ==="
  rm -rf "$OUT_BASE"
  mkdir -p "$OUT_BASE"
  make O="$OUT_BASE" gki_defconfig
  disable_btf "$OUT_BASE/.config"
  make O="$OUT_BASE" olddefconfig
  # Match shipping v2.1-ish: BORE/ADIOS already in gki_defconfig
  make -j"$JOBS" O="$OUT_BASE" Image 2>&1 | tee logs/baseline_build.log
  if [[ ! -f "$OUT_BASE/Module.symvers" && -f "$OUT_BASE/vmlinux.symvers" ]]; then cp -f "$OUT_BASE/vmlinux.symvers" "$OUT_BASE/Module.symvers"; fi
test -f "$OUT_BASE/Module.symvers"
  cp -f "$OUT_BASE/Module.symvers" "$STAMP_DIR/Module.symvers.baseline"
  log "baseline symvers saved"
fi

############################################
# Phase 1: wire SukiSU + SUSFS + DroidSpaces (proven scripts)
############################################
log "=== Fetch SukiSU pin $SUKISU_PIN ==="
rm -rf KernelSU susfs4ksu
git clone --depth=1 -b "$SUKISU_REF" "$SUKISU_REPO" KernelSU
if [[ -n "$SUKISU_PIN" ]]; then
  git -C KernelSU fetch --depth=1 origin "$SUKISU_PIN" || true
  git -C KernelSU checkout "$SUKISU_PIN" || git -C KernelSU reset --hard "$SUKISU_PIN" || true
fi
echo "[i] SukiSU $(git -C KernelSU rev-parse --short HEAD)"

log "=== Fetch SUSFS pin $SUSFS_PIN ==="
git clone --depth=1 -b "$SUSFS_BRANCH" "$SUSFS_REPO" susfs4ksu
git -C susfs4ksu fetch --depth=1 origin "$SUSFS_PIN" || true
git -C susfs4ksu checkout "$SUSFS_PIN" || git -C susfs4ksu reset --hard "$SUSFS_PIN" || true
echo "[i] SUSFS $(git -C susfs4ksu rev-parse --short HEAD)"

log "=== integrate-sukisu.sh ==="
bash scripts/susfs/integrate-sukisu.sh "$PWD/KernelSU" "$PWD/susfs4ksu" "$PWD"

if [[ "${SKIP_DROIDSPACES:-1}" == "1" ]]; then
  log "=== DroidSpaces SKIPPED (call/IMS isolation; match 2.1 SukiSU) ==="
else
  log "=== DroidSpaces integrate.sh (task_struct reserve) ==="
  bash scripts/droidspaces/integrate.sh
fi

log "=== Wire SukiSU into drivers/kernelsu (required for CONFIG_KSU) ==="
# integrate-* mutates KernelSU/ tree; link that kernel/ into drivers/
rm -f drivers/kernelsu
ln -sfn ../KernelSU/kernel drivers/kernelsu
if ! grep -q 'drivers/kernelsu/Kconfig' drivers/Kconfig; then
  sed -i '/^endmenu/i source "drivers/kernelsu/Kconfig"' drivers/Kconfig
fi
if ! grep -q 'obj-$(CONFIG_KSU)' drivers/Makefile; then
  printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> drivers/Makefile
fi
test -f drivers/kernelsu/Kconfig
test -d drivers/kernelsu


############################################
# Phase 2: configure premium
############################################
rm -rf "$OUT"
mkdir -p "$OUT"
make O="$OUT" gki_defconfig
# KSU root + KPM + SUSFS options (CONFIG_KSU is mandatory — without it Image has no SukiSU)
./scripts/config --file "$OUT/.config" --enable CONFIG_KSU || true
./scripts/config --file "$OUT/.config" --enable CONFIG_KPM || true
for o in KSU_SUSFS KSU_SUSFS_SUS_PATH KSU_SUSFS_SUS_MOUNT KSU_SUSFS_SUS_KSTAT \
         KSU_SUSFS_SPOOF_UNAME KSU_SUSFS_ENABLE_LOG KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS \
         KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG KSU_SUSFS_OPEN_REDIRECT KSU_SUSFS_SUS_MAP; do
  ./scripts/config --file "$OUT/.config" --enable "CONFIG_$o" || true
done
# DroidSpaces safe list (optional)
if [[ "${SKIP_DROIDSPACES:-1}" != "1" ]]; then
  while read -r opt; do
    [[ -z "$opt" || "$opt" =~ ^# ]] && continue
    ./scripts/config --file "$OUT/.config" --enable "CONFIG_$opt" || true
  done < scripts/droidspaces/droidspaces.config
else
  log "DroidSpaces config fragment skipped"
fi
# Premium fragment
if [[ -f scripts/kconfig/merge_config.sh ]]; then
  bash scripts/kconfig/merge_config.sh -O "$OUT" -m "$OUT/.config" theettam/configs/theettam_premium.config || true
fi
# Force-disable forbidden
for o in CGROUP_PIDS CGROUP_DEVICE NF_TABLES BRIDGE_NETFILTER NETFILTER_XT_MATCH_PHYSDEV; do
  ./scripts/config --file "$OUT/.config" --disable "CONFIG_$o" || true
done
make O="$OUT" olddefconfig
disable_btf "$OUT/.config"
make O="$OUT" olddefconfig

# Sanity forbidden off
for o in CGROUP_PIDS CGROUP_DEVICE NF_TABLES BRIDGE_NETFILTER; do
  if grep -q "^CONFIG_${o}=y" "$OUT/.config"; then
    echo "::error::FORBIDDEN CONFIG_${o}=y present"; exit 1
  fi
done
# Sanity required on
grep -q '^CONFIG_SCHED_BORE=y' "$OUT/.config" || echo "::warning::BORE not set (base may name differently)"
if [[ "${SKIP_DROIDSPACES:-1}" != "1" ]]; then
  grep -q '^CONFIG_SYSVIPC=y' "$OUT/.config" || { echo "::error::SYSVIPC missing after droidspaces"; exit 1; }
fi
grep -q '^CONFIG_KSU=y' "$OUT/.config" || { echo "::error::CONFIG_KSU not enabled — SukiSU will not work"; exit 1; }
grep -E '^CONFIG_KSU_SUSFS' "$OUT/.config" | head -5 || echo "::warning::no KSU_SUSFS options"
grep -q '^CONFIG_KPM=y' "$OUT/.config" || echo "::warning::CONFIG_KPM not set"


############################################
# Phase 3: build premium
############################################
log "=== PREMIUM build ==="
make -j"$JOBS" O="$OUT" Image 2>&1 | tee logs/premium_build.log
test -f "$OUT/arch/arm64/boot/Image"
test -f "$OUT/Module.symvers"
cp -f "$OUT/Module.symvers" "$STAMP_DIR/Module.symvers.premium"

############################################
# Phase 4: HARD GATE
############################################
log "=== KABI gate ==="
bash theettam/scripts/kabi_symvers_gate.sh \
  "$STAMP_DIR/Module.symvers.baseline" \
  "$STAMP_DIR/Module.symvers.premium" \
  "$STAMP_DIR/Module.symvers.diff.txt"
log "KABI gate PASS"
cp -f "$OUT/arch/arm64/boot/Image" dist/Image-premium-sukisu
# Package note
cat > dist/PREMIUM_KABI_REPORT.md <<EOF
# Premium KABI report
- Base: $(git rev-parse --short HEAD)
- Baseline symvers: Module.symvers.baseline
- Premium symvers: Module.symvers.premium
- Gate: PASS (see Module.symvers.diff.txt)
- Pins: SukiSU $SUKISU_PIN SUSFS $SUSFS_PIN
- Forbidden configs forced off: CGROUP_PIDS CGROUP_DEVICE NF_TABLES BRIDGE_NETFILTER
EOF
log "DONE Image at dist/Image-premium-sukisu"
