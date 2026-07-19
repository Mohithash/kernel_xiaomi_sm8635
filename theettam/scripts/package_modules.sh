#!/usr/bin/env bash
# Package kernel modules for Theettam.
#
# Why this exists:
#   Devs often say "we have a kernel but nobody is making modules."
#   GKI phones load hundreds of .ko from vendor_dlkm/system_dlkm.
#   Custom kernels that only ship Image leave:
#     - no rebuilt .ko matching the new kernel CRC/version
#     - no package of optional Theettam extras (Boeffla, WireGuard, …)
#     - ROM/device trees with nothing to put in vendor_dlkm
#
# This script:
#   1) modules_install into a staging tree
#   2) Build a FULL modules tarball (for ROM/devs rebuilding dlkm)
#   3) Stage Theettam EXTRA modules into AnyKernel modules/ for flash
#
# Usage (from kernel root, after a successful Image build):
#   OUT=out bash theettam/scripts/package_modules.sh
set -euo pipefail

DIR=$(readlink -f .)
OUT="${OUT:-out}"
CLANG_BIN="${THEETTAM_CLANG:-$(readlink -f "${DIR}/../clang/bin")}"
export PATH="${CLANG_BIN}:${PATH}"
export ARCH=arm64
export LLVM=1
export LLVM_IAS=1

MOD_STAGE="${DIR}/.mod_stage"
MOD_INSTALL="${MOD_STAGE}/lib/modules"
AK3_MOD="${DIR}/anykernel/modules"
ARTIFACTS="${DIR}/dist"
RELEASE=$(cat "${OUT}/include/config/kernel.release" 2>/dev/null || uname -r)

echo "==== Theettam package_modules ===="
echo "OUT=$OUT  release=$RELEASE"

if [ ! -f "${OUT}/.config" ]; then
  echo "FATAL: ${OUT}/.config missing — build the kernel first"
  exit 1
fi

rm -rf "$MOD_STAGE"
mkdir -p "$MOD_STAGE" "$ARTIFACTS"

# Ensure modules built; tolerate all-built-in kernels
make -j"$(nproc)" O="$OUT" modules \
  CC=clang LD=ld.lld AR=llvm-ar NM=llvm-nm \
  OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip \
  HOSTCC=clang HOSTCXX=clang++ HOSTLD=ld.lld || true
if [ ! -f "$OUT/modules.order" ]; then
  echo "WARN: no modules.order — creating empty (all-built-in?)"
  : > "$OUT/modules.order"
fi

# Install all built modules (and modules.dep / modules.alias …)
set +e
make -j"$(nproc)" O="$OUT" modules_install \
  INSTALL_MOD_PATH="$MOD_STAGE" \
  INSTALL_MOD_STRIP=1 \
  CC=clang LD=ld.lld AR=llvm-ar NM=llvm-nm \
  OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip \
  HOSTCC=clang HOSTCXX=clang++ HOSTLD=ld.lld
MI_RC=$?
set -e
if [ "$MI_RC" -ne 0 ]; then
  echo "WARN: modules_install rc=$MI_RC — continuing Image-only packaging"
  mkdir -p "$MOD_INSTALL/$(cat $OUT/include/config/kernel.release 2>/dev/null || echo unknown)"
fi

# Resolve install dir (lib/modules/<release>)
INST=$(find "$MOD_INSTALL" -mindepth 1 -maxdepth 1 -type d | head -1)
if [ -z "$INST" ]; then
  echo "WARN: no modules installed (all built-in?). Still writing empty package markers."
  mkdir -p "${MOD_INSTALL}/${RELEASE}"
  INST="${MOD_INSTALL}/${RELEASE}"
fi
RELEASE_REAL=$(basename "$INST")
echo "installed modules under: $INST"
find "$INST" -name '*.ko' | wc -l | xargs -I{} echo "ko_count={}"

# Full tarball for ROM / vendor_dlkm rebuilders
FULL_TGZ="${ARTIFACTS}/Theettam-modules-full-${RELEASE_REAL}.tar.gz"
tar -C "$MOD_STAGE" -czf "$FULL_TGZ" .
echo "FULL_MODULES=$FULL_TGZ ($(du -h "$FULL_TGZ" | cut -f1))"

# Theettam EXTRA module allow-list (ship in AnyKernel zip)
# Only ship modules we own / optionally added — do NOT replace stock vendor_dlkm.
EXTRAS=(
  boeffla_wl_blocker
  wireguard
)

rm -rf "$AK3_MOD"
mkdir -p "${AK3_MOD}/system/lib/modules"

EXTRA_COUNT=0
for name in "${EXTRAS[@]}"; do
  while IFS= read -r -d '' ko; do
    base=$(basename "$ko")
    cp -f "$ko" "${AK3_MOD}/system/lib/modules/${base}"
    EXTRA_COUNT=$((EXTRA_COUNT + 1))
    echo "  + ak3 extra: $base"
  done < <(find "$INST" -name "${name}.ko" -print0 2>/dev/null || true)
done

# modules.load for extras (order)
: > "${AK3_MOD}/system/lib/modules/modules.load"
for name in "${EXTRAS[@]}"; do
  if [ -f "${AK3_MOD}/system/lib/modules/${name}.ko" ]; then
    echo "$name" >> "${AK3_MOD}/system/lib/modules/modules.load"
  fi
done

# Manifest for flashers / CI
cat > "${AK3_MOD}/README.txt" <<MAN
Theettam modular extras
=======================
These .ko match THIS kernel build (${RELEASE_REAL}).

Root (SukiSU) + SUSFS stay built-in to the Image — they are NOT modules.
Stock vendor/system_dlkm modules still come from the ROM; we keep KMI
compatible so they continue to load.

Full module tree (all .ko from this build) is in dist/ as:
  Theettam-modules-full-*.tar.gz
Use that if you rebuild vendor_dlkm / system_dlkm for a ROM.

Flash path: AnyKernel do.modules=1 + do.systemless=1 installs extras
via Magisk/KSU helper module (ak3-helper) without writing vendor partitions.
MAN

# List artifact of extras only
EXTRAS_TGZ="${ARTIFACTS}/Theettam-modules-extras-${RELEASE_REAL}.tar.gz"
if [ "$EXTRA_COUNT" -gt 0 ]; then
  tar -C "$AK3_MOD" -czf "$EXTRAS_TGZ" .
  echo "EXTRAS_MODULES=$EXTRAS_TGZ count=$EXTRA_COUNT"
else
  echo "WARN: no extra .ko found (features built-in or not built). Empty modules dir kept."
  # placeholder so zip structure is stable
  mkdir -p "${AK3_MOD}/system/lib/modules"
  : > "${AK3_MOD}/system/lib/modules/.theettam_modular"
fi

# Write depmod-friendly note
cat > "${ARTIFACTS}/MODULES_MANIFEST.txt" <<MAN
release=${RELEASE_REAL}
full_tarball=$(basename "$FULL_TGZ")
extras_count=${EXTRA_COUNT}
extras_list=$(tr '\n' ' ' < "${AK3_MOD}/system/lib/modules/modules.load" 2>/dev/null || true)
built_in_must=KSU KPM KSU_SUSFS (SukiSU+SUSFS — never modules)
modular_policy=optional Theettam extras as =m; full tree via modules_install
MAN
cat "${ARTIFACTS}/MODULES_MANIFEST.txt"
echo "==== package_modules done ===="
