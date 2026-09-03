#!/bin/bash
# build-flavor.sh — build one Theettam flavor exactly the way the release
# workflow (.github/workflows/build-theettam-20.yml) does, so a local build on
# ServerHive and a CI build are the same thing.
#
#   scripts/ci/build-flavor.sh <flavor>
#
# Flavors:
#   plain                    no root (KABI baseline / bisect)
#   ksun-plain               KernelSU-Next, no SUSFS
#   ksun-susfs               KernelSU-Next + SUSFS (hand-port, integrate.sh)
#   sukisu-susfs             SukiSU-Ultra + SUSFS   (integrate-sukisu.sh)
#   ksun-susfs-droidspaces   KernelSU-Next + SUSFS + DroidSpaces
#   resukisu-susfs           ReSukiSU + SUSFS (native driver, fs-side only)
#   premium                  SukiSU-Ultra + SUSFS + DroidSpaces
#   apatch                   clean Image, patched post-build with KernelPatch
#
# The SUSFS/DroidSpaces integration scripts MODIFY TRACKED FILES (fs/*, kernel/*,
# include/linux/sched.h, drivers/Kconfig, ...). Run this in a dedicated git
# worktree, never in your main checkout:
#   git worktree add --detach /path/wt-sukisu theettam-2.7
#   (cd /path/wt-sukisu && scripts/ci/build-flavor.sh sukisu-susfs)
# To rebuild in the same worktree: git reset --hard <ref> && git clean -ffdx -e out
# (double -f: KernelSU/ and susfs4ksu/ are nested git repos, single -f skips them).
#
# Environment:
#   CLANG_DIR     toolchain root with bin/clang   (default: $HOME/clang)
#   OUT           kbuild output dir               (default: out)
#   JOBS          make -j                         (default: nproc)
#   ZIP_PREFIX    zip name prefix                 (default: Theettam)
#   ZIP_VERSION   version string in the zip name  (default: dev)
#   DIST          where zip/Image/symvers land    (default: dist)
#   APATCH_SUPERKEY  superkey baked into the APatch Image (default: from pins.env)
#   ALLOW_DIRTY=1 skip the clean-tree check
#   SKIP_ZIP=1    do not package
#   USE_CCACHE=0  do not wrap clang in ccache even if installed
#   KMI_STRICT=1  fail if scripts/ci/kmi-baseline/<flavor>.symvers is missing (CI sets this)
set -euo pipefail

FLAVOR="${1:-}"
[ -n "$FLAVOR" ] || { sed -n '2,40p' "$0"; exit 2; }

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
# shellcheck disable=SC1091
source scripts/ci/pins.env

OUT="${OUT:-out}"
DIST="${DIST:-dist}"
JOBS="${JOBS:-$(nproc --all)}"
CLANG_DIR="${CLANG_DIR:-$HOME/clang}"
ZIP_PREFIX="${ZIP_PREFIX:-Theettam}"
ZIP_VERSION="${ZIP_VERSION:-dev}"
export ARCH=arm64 SUBARCH=arm64 LLVM=1 LLVM_IAS=1
export KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-build}" KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST:-localhost}"
export PATH="$CLANG_DIR/bin:$PATH"

log()  { echo "[$(date -u +%H:%M:%S)] $*"; }
die()  { echo "::error::$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# ---- flavor table (mirror of the CI matrix) --------------------------------
ROOT_ENGINE=none; SUSFS=none; INTEGRATE=""; DROIDSPACES=0; KPM=0; APATCH=0
case "$FLAVOR" in
  plain)                  ZIPNAME=NoRoot;                                  LABEL="no root" ;;
  ksun-plain)             ROOT_ENGINE=ksun;    ZIPNAME=KSUN${KSUN_TAG#v};                        LABEL="KernelSU-Next ${KSUN_TAG}" ;;
  ksun-susfs)             ROOT_ENGINE=ksun;    SUSFS=shim; INTEGRATE=integrate.sh;        ZIPNAME=KSUN${KSUN_TAG#v}-SUSFS${SUSFS_EXPECT_VERSION#v};   LABEL="KernelSU-Next ${KSUN_TAG} + SUSFS ${SUSFS_EXPECT_VERSION}" ;;
  sukisu-susfs)           ROOT_ENGINE=sukisu;  SUSFS=shim; INTEGRATE=integrate-sukisu.sh; ZIPNAME=SukiSU-Ultra-SUSFS${SUSFS_EXPECT_VERSION#v};        LABEL="SukiSU Ultra + SUSFS ${SUSFS_EXPECT_VERSION}" ;;
  ksun-susfs-droidspaces) ROOT_ENGINE=ksun;    SUSFS=shim; INTEGRATE=integrate.sh; DROIDSPACES=1; ZIPNAME=KSUN${KSUN_TAG#v}-SUSFS${SUSFS_EXPECT_VERSION#v}-DroidSpaces; LABEL="KernelSU-Next + SUSFS + DroidSpaces" ;;
  resukisu-susfs)         ROOT_ENGINE=resukisu; SUSFS=native;                             ZIPNAME=ReSukiSU-SUSFS${SUSFS_EXPECT_VERSION#v};             LABEL="ReSukiSU + SUSFS ${SUSFS_EXPECT_VERSION}" ;;
  premium)                ROOT_ENGINE=sukisu;  SUSFS=shim; INTEGRATE=integrate-sukisu.sh; DROIDSPACES=1; ZIPNAME=Premium-SukiSU-SUSFS-DroidSpaces; LABEL="Premium: SukiSU Ultra + SUSFS + DroidSpaces" ;;
  apatch)                 APATCH=1;            ZIPNAME=APatch-KernelPatch${KP_VERSION};   LABEL="APatch / KernelPatch ${KP_VERSION}" ;;
  *) die "unknown flavor '$FLAVOR'" ;;
esac

# ---- preconditions ----------------------------------------------------------
have clang || die "clang not in PATH (CLANG_DIR=$CLANG_DIR)"
log "flavor=$FLAVOR  clang: $(clang --version | head -1)"
grep -q '^SUBLEVEL = 175' Makefile || die "base is not 6.1.175"
grep -q '^CONFIG_SCHED_BORE=y' arch/arm64/configs/gki_defconfig || die "BORE missing from gki_defconfig"
grep -q '^CONFIG_MQ_IOSCHED_ADIOS=y' arch/arm64/configs/gki_defconfig || die "ADIOS missing from gki_defconfig"
if [ "${ALLOW_DIRTY:-0}" != "1" ]; then
  [ -z "$(git status --porcelain --untracked-files=no)" ] || die "tree has uncommitted changes; run in a fresh worktree or set ALLOW_DIRTY=1"
  for d in KernelSU susfs4ksu; do [ -e "$d" ] && die "stale $d/ present; remove it or set ALLOW_DIRTY=1"; done
fi
for p in SUSFS_PIN SUKISU_PIN RESUKISU_PIN; do
  [[ "${!p}" =~ ^[0-9a-f]{40}$ ]] || die "$p in scripts/ci/pins.env is not a full 40-char sha"
done

# ---- 1. root driver -----------------------------------------------------------
fetch_driver() {
  rm -rf KernelSU
  case "$ROOT_ENGINE" in
    ksun)
      # No --depth: KSUN's Kbuild derives KSU_VERSION from `git rev-list --count HEAD`
      # and a shallow clone yields 30001 (manager then reports an ancient driver).
      git clone --quiet --branch "$KSUN_TAG" "$KSUN_REPO" KernelSU
      local cnt; cnt=$(git -C KernelSU rev-list --count HEAD)
      [ "$cnt" -gt 100 ] || die "KernelSU-Next clone looks shallow (rev-list count $cnt)" ;;
    sukisu)
      git clone --quiet -b "$SUKISU_BRANCH" "$SUKISU_REPO" KernelSU
      git -C KernelSU checkout --quiet "$SUKISU_PIN"
      # SukiSU derives KSU_VERSION from `git rev-list --count main`. Give it a
      # real main ref (pin + the kernel-side main commits) or it reports 13000.
      if grep -q 'REPO_BRANCH := main' KernelSU/kernel/Kbuild 2>/dev/null; then
        git -C KernelSU fetch --quiet origin main
        git -C KernelSU config user.email ci@theettam; git -C KernelSU config user.name ci
        for c in $SUKISU_MAIN_CHERRYPICKS; do
          [[ "$c" =~ ^[0-9a-f]{40}$ ]] || die "SUKISU_MAIN_CHERRYPICKS entry '$c' is not a full sha"
          git -C KernelSU cherry-pick -x "$c" >/dev/null 2>&1 \
            || { git -C KernelSU cherry-pick --abort 2>/dev/null || true; die "SukiSU main commit $c did not cherry-pick onto $SUKISU_BRANCH"; }
          log "  [+] integrated SukiSU main commit ${c:0:10}"
        done
        git -C KernelSU branch -f main HEAD
        local cnt; cnt=$(git -C KernelSU rev-list --count main)
        log "  SukiSU count(main)=$cnt -> KSU_VERSION=$((40000 + cnt - 2815))"
        [ $((40000 + cnt - 2815)) -gt 30000 ] || die "SukiSU version still low; count path broken"
      fi ;;
    resukisu)
      git clone --quiet "$RESUKISU_REPO" KernelSU
      git -C KernelSU checkout --quiet "$RESUKISU_PIN" ;;
  esac
  log "driver @ $(git -C KernelSU rev-parse --short HEAD) ($ROOT_ENGINE)"
}

fetch_susfs() {
  rm -rf susfs4ksu
  git clone --quiet -b "$SUSFS_BRANCH" "$SUSFS_REPO" susfs4ksu
  git -C susfs4ksu checkout --quiet "$SUSFS_PIN"
  local v; v="$(sed -n 's/.*SUSFS_VERSION[^"]*"\([^"]*\)".*/\1/p' susfs4ksu/kernel_patches/include/linux/susfs.h)"
  [ "$v" = "$SUSFS_EXPECT_VERSION" ] || die "expected SUSFS $SUSFS_EXPECT_VERSION, got '$v' at $SUSFS_PIN"
  log "susfs4ksu $v @ ${SUSFS_PIN:0:10}"
}

check_rejects() {
  local rej; rej="$(find . -path ./"$OUT" -prune -o -name '*.rej' -print 2>/dev/null || true)"
  [ -z "$rej" ] || { echo "$rej" | while read -r r; do echo "== $r =="; cat "$r"; done; die "patch rejects present"; }
}

if [ "$ROOT_ENGINE" != none ]; then
  fetch_driver
  ln -sfn ../KernelSU/kernel drivers/kernelsu
  grep -q 'drivers/kernelsu/Kconfig' drivers/Kconfig || sed -i '/^endmenu/i source "drivers/kernelsu/Kconfig"' drivers/Kconfig
  grep -q 'obj-$(CONFIG_KSU)' drivers/Makefile || printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> drivers/Makefile
fi
if [ "$SUSFS" != none ]; then fetch_susfs; fi

# ---- 2. SUSFS integration ---------------------------------------------------------
case "$SUSFS" in
  shim)   log "integrating SUSFS via scripts/susfs/$INTEGRATE"
          bash "scripts/susfs/$INTEGRATE" "$PWD/KernelSU" "$PWD/susfs4ksu" "$PWD"; check_rejects ;;
  native) log "integrating SUSFS fs-side only (native driver)"
          bash scripts/susfs/integrate-native.sh "$PWD/susfs4ksu" "$PWD"; check_rejects ;;
esac
if [ -f KernelSU/kernel/hook/lsm_hook.c ]; then
  bash scripts/fix-lsm-hook-lto.sh KernelSU/kernel/hook/lsm_hook.c
fi

# ---- 3. DroidSpaces -------------------------------------------------------------------
if [ "$DROIDSPACES" = 1 ]; then
  bash scripts/droidspaces/integrate.sh "$PWD"
  grep -q 'ANDROID_KABI_USE(6, struct sysv_sem sysvsem)' include/linux/sched.h || die "SYSVIPC relocation missing"
  grep -qE '^\s*/\* struct sysv_sem' include/linux/sched.h || die "original sysvsem declaration still live"
  log "SYSVIPC relocated into KABI reserve slots 6/7/8"
fi

# ---- 4. configure ------------------------------------------------------------------------
C=./scripts/config
make -s -j"$JOBS" O="$OUT" gki_defconfig
CFG="$OUT/.config"
if [ "$ROOT_ENGINE" != none ]; then $C --file "$CFG" -e KSU; fi
if [ "$KPM" = 1 ]; then
  grep -rqE '^\s*config KPM\s*$' --include=Kconfig . || die "CONFIG_KPM is not a Kconfig symbol in this tree"
  $C --file "$CFG" -e KPM
fi
if [ "$SUSFS" != none ]; then
  for o in KSU_SUSFS KSU_SUSFS_SUS_PATH KSU_SUSFS_SUS_MOUNT KSU_SUSFS_SUS_KSTAT KSU_SUSFS_SPOOF_UNAME \
           KSU_SUSFS_ENABLE_LOG KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG \
           KSU_SUSFS_OPEN_REDIRECT KSU_SUSFS_SUS_MAP; do $C --file "$CFG" -e "$o"; done
fi
if [ "$DROIDSPACES" = 1 ]; then
  for o in $(grep -v '^#' scripts/droidspaces/droidspaces.config); do
    grep -rqE "^\s*(menu)?config $o\s*$" --include=Kconfig . || die "CONFIG_$o is not a Kconfig symbol in this tree"
    $C --file "$CFG" -e "$o"
  done
fi
make -s -j"$JOBS" O="$OUT" olddefconfig

log "config verification"
if [ "$ROOT_ENGINE" != none ]; then grep -q '^CONFIG_KSU=y' "$CFG" || die "KSU not enabled"; fi
for o in SCHED_BORE MQ_IOSCHED_ADIOS DAMON_PADDR DAMON_RECLAIM DAMON_LRU_SORT ZRAM_WRITEBACK BOEFFLA_WL_BLOCKER DEBUG_INFO_BTF; do
  grep -qE "^CONFIG_$o=(y|m)" "$CFG" || die "CONFIG_$o dropped in olddefconfig"
done
if [ "$SUSFS" != none ]; then grep -q '^CONFIG_KSU_SUSFS=y' "$CFG" || die "SUSFS not enabled in .config"; fi
if [ "$KPM" = 1 ]; then grep -q '^CONFIG_KPM=y' "$CFG" || die "CONFIG_KPM=y dropped in olddefconfig"; fi
if [ "$DROIDSPACES" = 1 ]; then
  for o in $(grep -v '^#' scripts/droidspaces/droidspaces.config); do
    grep -qE "^CONFIG_$o=(y|m)" "$CFG" || die "CONFIG_$o did not enable"
  done
fi

# ---- 5. build ---------------------------------------------------------------------------------
export KBUILD_COMPILER_STRING="$(clang --version | head -n1)"
CCW=clang; if [ "${USE_CCACHE:-1}" = 1 ] && have ccache; then CCW="ccache clang"; fi
log "build: make -j$JOBS O=$OUT CC='$CCW'"
make -j"$JOBS" O="$OUT" CC="$CCW" 2>&1 | tee "$OUT/build.log" | grep -E --line-buffered 'error:|Error [0-9]|LD      vmlinux$|OBJCOPY arch/arm64/boot/Image' || true
[ "${PIPESTATUS[0]}" = 0 ] || die "kernel build failed (see $OUT/build.log)"
IMG="$OUT/arch/arm64/boot/Image"; [ -f "$IMG" ] || die "no Image"
KREL="$(cat "$OUT/include/config/kernel.release")"

# ---- 5b. KMI gate (docs/BOOT-NOTES.md Rule 2) ------------------------------------------------
# Stock vendor_dlkm modules are prebuilt against the boot-tested Image. A config or
# merge that shifts an exported symbol's CRC compiles fine and bootloops. Compare
# every export CRC in Module.symvers against the baseline recorded from the
# boot-tested build of this flavor.
KMI_BASE="scripts/ci/kmi-baseline/$FLAVOR.symvers"
if [ -f "$KMI_BASE" ]; then
  if scripts/ci/symvers-diff.sh "$KMI_BASE" "$OUT/Module.symvers" > "$OUT/kmi-diff.txt" 2> "$OUT/kmi-summary.txt"; then
    log "KMI gate: $(cat "$OUT/kmi-summary.txt") vs $KMI_BASE"
  else
    head -40 "$OUT/kmi-diff.txt"; cat "$OUT/kmi-summary.txt"
    die "KMI CRC drift against the boot-tested baseline $KMI_BASE (full list: $OUT/kmi-diff.txt). This Image would not load the stock vendor modules."
  fi
elif [ "${KMI_STRICT:-0}" = 1 ]; then
  die "no KMI baseline at $KMI_BASE (KMI_STRICT=1)"
else
  log "no KMI baseline at $KMI_BASE; gate skipped (KMI_STRICT=1 to require it)"
fi

# ---- 6. APatch: patch the compiled Image ------------------------------------------------------
if [ "$APATCH" = 1 ]; then
  mkdir -p "$OUT/kp"
  curl -fsSLo "$OUT/kp/kptools" "https://github.com/bmax121/KernelPatch/releases/download/${KP_VERSION}/kptools-linux"
  curl -fsSLo "$OUT/kp/kpimg"   "https://github.com/bmax121/KernelPatch/releases/download/${KP_VERSION}/kpimg-android"
  chmod +x "$OUT/kp/kptools"
  "$OUT/kp/kptools" -p -i "$IMG" -k "$OUT/kp/kpimg" -s "${APATCH_SUPERKEY:-$KP_SUPERKEY_DEFAULT}" -o "$IMG.kp"
  mv -f "$IMG.kp" "$IMG"
  "$OUT/kp/kptools" -l -i "$IMG" | tee "$OUT/kp-list.txt"
  grep -qiE 'superkey|kernelpatch' "$OUT/kp-list.txt" || die "KernelPatch not applied"
  log "KernelPatch $KP_VERSION applied"
fi

# ---- 7. artifacts -----------------------------------------------------------------------------------
mkdir -p "$DIST"
cp -f "$IMG" "$DIST/Image-$FLAVOR"
cp -f "$OUT/Module.symvers" "$DIST/Module.symvers-$FLAVOR"
cp -f "$CFG" "$DIST/config-$FLAVOR"
if [ "${SKIP_ZIP:-0}" != 1 ]; then
  AK="$OUT/AnyKernel3"; rm -rf "$AK"; cp -r anykernel "$AK"; cp -f "$IMG" "$AK/Image"
  sed -i "s/^kernel.string=.*/kernel.string=Theettam · $LABEL/" "$AK/anykernel.sh"
  printf '%s\n%s\n%s\n' "Theettam $ZIP_VERSION · $LABEL" "POCO F6 / Redmi Turbo 3 (peridot · SM8635)" "GKI $KREL" > "$AK/version"
  ZIP="$ZIP_PREFIX-$ZIP_VERSION-$ZIPNAME-peridot-$KREL.zip"
  ( cd "$AK" && zip -q -r9 "$OLDPWD/$DIST/$ZIP" . -x '.git*' )
  log "zip: $DIST/$ZIP ($(stat -c%s "$DIST/$ZIP") bytes)"
fi
log "done: flavor=$FLAVOR kernel.release=$KREL Image=$DIST/Image-$FLAVOR symvers=$DIST/Module.symvers-$FLAVOR"
