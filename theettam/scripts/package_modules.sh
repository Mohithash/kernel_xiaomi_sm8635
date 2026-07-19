#!/usr/bin/env bash
# Package modules + stage AnyKernel extras. Image-first: do not recompile.
set -euo pipefail
DIR=$(readlink -f .)
OUT="${OUT:-out}"
CLANG_BIN="${THEETTAM_CLANG:-$(readlink -f "${DIR}/../clang/bin" 2>/dev/null || echo)}"
export PATH="${CLANG_BIN}:${PATH}"
export ARCH=arm64 LLVM=1 LLVM_IAS=1

MOD_STAGE="${DIR}/.mod_stage"
MOD_INSTALL="${MOD_STAGE}/lib/modules"
AK3_MOD="${DIR}/anykernel/modules"
ARTIFACTS="${DIR}/dist"
RELEASE=$(cat "${OUT}/include/config/kernel.release" 2>/dev/null || echo unknown)

echo "==== Theettam package_modules ===="
echo "OUT=$OUT  release=$RELEASE"
test -f "${OUT}/.config" || { echo "FATAL: no ${OUT}/.config"; exit 1; }
mkdir -p "$MOD_STAGE" "$ARTIFACTS" "${AK3_MOD}/system/lib/modules"

if [ -f "${OUT}/modules.order" ] && [ -s "${OUT}/modules.order" ]; then
  echo "modules_install..."
  set +e
  make -j"$(nproc)" O="$OUT" modules_install \
    INSTALL_MOD_PATH="$MOD_STAGE" INSTALL_MOD_STRIP=1 \
    CC=clang LD=ld.lld AR=llvm-ar NM=llvm-nm \
    OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip \
    HOSTCC=clang HOSTCXX=clang++ HOSTLD=ld.lld
  echo "modules_install rc=$?"
  set -e
else
  echo "WARN: no modules.order (or empty) — Image-only package"
  mkdir -p "${MOD_INSTALL}/${RELEASE}"
fi

INST=$(find "$MOD_INSTALL" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1 || true)
[ -n "$INST" ] || INST="${MOD_INSTALL}/${RELEASE}"
mkdir -p "$INST"
RELEASE_REAL=$(basename "$INST")
ko_count=$(find "$INST" -name '*.ko' 2>/dev/null | wc -l | tr -d ' ')
echo "ko_count=${ko_count} under $INST"

FULL_TGZ="${ARTIFACTS}/Theettam-modules-full-${RELEASE_REAL}.tar.gz"
tar -C "$MOD_STAGE" -czf "$FULL_TGZ" . 2>/dev/null || tar -czf "$FULL_TGZ" -T /dev/null
echo "FULL_MODULES=$FULL_TGZ"

EXTRAS=(boeffla_wl_blocker wireguard)
rm -rf "$AK3_MOD"
mkdir -p "${AK3_MOD}/system/lib/modules"
EXTRA_COUNT=0
for name in "${EXTRAS[@]}"; do
  while IFS= read -r -d '' ko; do
    cp -f "$ko" "${AK3_MOD}/system/lib/modules/$(basename "$ko")"
    EXTRA_COUNT=$((EXTRA_COUNT + 1))
    echo "  + ak3 extra: $(basename "$ko")"
  done < <(find "$INST" -name "${name}.ko" -print0 2>/dev/null || true)
done
: > "${AK3_MOD}/system/lib/modules/modules.load"
for name in "${EXTRAS[@]}"; do
  [ -f "${AK3_MOD}/system/lib/modules/${name}.ko" ] && echo "$name" >> "${AK3_MOD}/system/lib/modules/modules.load"
done
cat > "${AK3_MOD}/README.txt" <<MAN
Theettam modular extras for ${RELEASE_REAL}
Root/SUSFS stay built-in. Stock vendor_dlkm from ROM.
MAN
if [ "$EXTRA_COUNT" -gt 0 ]; then
  tar -C "$AK3_MOD" -czf "${ARTIFACTS}/Theettam-modules-extras-${RELEASE_REAL}.tar.gz" .
else
  mkdir -p "${AK3_MOD}/system/lib/modules"
  : > "${AK3_MOD}/system/lib/modules/.theettam_modular"
fi
cat > "${ARTIFACTS}/MODULES_MANIFEST.txt" <<MAN
release=${RELEASE_REAL}
extras_count=${EXTRA_COUNT}
MAN
cat "${ARTIFACTS}/MODULES_MANIFEST.txt"
echo "==== package_modules done ===="
