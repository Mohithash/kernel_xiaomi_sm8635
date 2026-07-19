#!/usr/bin/env bash
# Theettam production build — GKI 6.1.175 / peridot / VoltageOS
# Respects KMI: KMI_SYMBOL_LIST_STRICT_MODE=1
set -euo pipefail
# Research Phase-1 build env
if [ -f theettam/build/build.config.theettam ]; then
  # shellcheck disable=SC1091
  source theettam/build/build.config.theettam
fi
export KMI_SYMBOL_LIST_STRICT_MODE="${KMI_SYMBOL_LIST_STRICT_MODE:-1}"
export TRIM_NONLISTED_KMI="${TRIM_NONLISTED_KMI:-1}"


DIR=$(readlink -f .)
MAIN=$(readlink -f "${DIR}/..")
CLANG_BIN="${THEETTAM_CLANG:-$MAIN/clang/bin}"
export PATH="${CLANG_BIN}:$PATH"
export ARCH=arm64
export SUBARCH=arm64
export KMI_SYMBOL_LIST_STRICT_MODE=1
export LLVM=1
export LLVM_IAS=1

CLANG="${CLANG_BIN}/clang"
JOBS="${THEETTAM_JOBS:-$(nproc)}"
OUT="${OUT:-out}"

DEFCONFIGS=(
  gki_defconfig
  vendor/pineapple_GKI.config
  vendor/peridot_GKI.config
  vendor/theettam_GKI.config
)

# Drop missing fragments gracefully
ARGS=()
for f in "${DEFCONFIGS[@]}"; do
  if [ -f "arch/arm64/configs/${f}" ] || [ -f "arch/arm64/configs/${f#vendor/}" ]; then
    ARGS+=("$f")
  elif [ -f "arch/arm64/configs/vendor/${f#vendor/}" ]; then
    ARGS+=("vendor/${f#vendor/}")
  else
    echo "[!] skip missing $f"
  fi
done

echo "==== Theettam build ===="
echo "clang: $($CLANG --version | head -1)"
echo "defconfig: ${ARGS[*]}"
echo "jobs: $JOBS  KMI_SYMBOL_LIST_STRICT_MODE=$KMI_SYMBOL_LIST_STRICT_MODE"

make O="$OUT" "${ARGS[@]}" \
  CC="$CLANG" LD=ld.lld AR=llvm-ar NM=llvm-nm \
  OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip \
  HOSTCC="$CLANG" HOSTCXX="${CLANG_BIN}/clang++" HOSTLD=ld.lld

# Ensure BORE + PELT + blocker defaults are forced even if fragment merge drops them
scripts/config --file "$OUT/.config" \
  -e SCHED_BORE \
  -e MQ_IOSCHED_ADIOS \
  -e MQ_IOSCHED_DEFAULT_ADIOS \
  -e BOEFFLA_WL_BLOCKER \
  -e USER_NS \
  -e NAMESPACES \
  -e VETH \
  -e MACVLAN \
  -e NETFILTER_XT_MATCH_MULTIPORT \
  -e KALLSYMS \
  -e KALLSYMS_ALL \
  -e KPM 2>/dev/null || true

# SUSFS / KSU if present after integrate_root.sh
for o in KSU KSU_SUSFS KSU_SUSFS_SUS_PATH KSU_SUSFS_SUS_MOUNT KSU_SUSFS_SUS_KSTAT \
         KSU_SUSFS_SUS_MAP KSU_SUSFS_SPOOF_UNAME KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG \
         KSU_SUSFS_OPEN_REDIRECT KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS; do
  scripts/config --file "$OUT/.config" -e "$o" 2>/dev/null || true
done
scripts/config --file "$OUT/.config" -d KSU_SUSFS_ENABLE_LOG 2>/dev/null || true

make O="$OUT" olddefconfig CC="$CLANG" LD=ld.lld

make -j"$JOBS" O="$OUT" \
  CC="$CLANG" LD=ld.lld AR=llvm-ar NM=llvm-nm \
  OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip \
  HOSTCC="$CLANG" HOSTCXX="${CLANG_BIN}/clang++" HOSTLD=ld.lld

ZIMG="$OUT/arch/arm64/boot/Image.gz"
IMG="$OUT/arch/arm64/boot/Image"
if [ ! -f "$ZIMG" ] && [ -f "$IMG" ]; then
  gzip -9 -c "$IMG" > "$ZIMG"
fi
test -f "$ZIMG" -o -f "$IMG"

# Modules (the missing piece: Image alone is not enough for GKI/devs)
bash theettam/scripts/package_modules.sh

# Package AnyKernel zip (Image + modular extras)
TIME=$(date -u +%Y%m%d-%H%M%S)
NAME="Theettam-Kernel-peridot-${TIME}.zip"
rm -rf .ak3_pack
mkdir -p .ak3_pack
cp -a anykernel/* .ak3_pack/ 2>/dev/null || true
if [ -f "$ZIMG" ]; then cp -f "$ZIMG" .ak3_pack/Image.gz
else cp -f "$IMG" .ak3_pack/Image; gzip -9 -c .ak3_pack/Image > .ak3_pack/Image.gz; fi
( cd .ak3_pack && zip -r9 "../$NAME" . )
echo "PACKAGED $NAME"
ls -lah "$NAME"
ls -lah dist/ 2>/dev/null || true
