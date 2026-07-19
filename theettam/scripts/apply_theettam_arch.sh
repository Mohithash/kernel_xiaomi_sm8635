#!/usr/bin/env bash
# Apply Theettam architecture package onto a checked-out kernel tree (cwd = kernel root)
set -euo pipefail
PKG="${1:-}"
if [ -z "$PKG" ] || [ ! -d "$PKG/arch" ]; then
  echo "Usage: $0 /path/to/theettam_arch"
  exit 1
fi

echo "[*] config fragment"
mkdir -p arch/arm64/configs/vendor
cp -f "$PKG/arch/arm64/configs/vendor/theettam_GKI.config" arch/arm64/configs/vendor/

echo "[*] boeffla driver"
mkdir -p drivers/misc/boeffla_wl_blocker
cp -f "$PKG/drivers/misc/boeffla_wl_blocker/"* drivers/misc/boeffla_wl_blocker/

# Kconfig / Makefile glue (idempotent)
if ! grep -q BOEFFLA_WL_BLOCKER drivers/misc/Kconfig 2>/dev/null; then
  # insert before last endmenu in file if possible
  if grep -q '^endmenu' drivers/misc/Kconfig; then
    sed -i '/^endmenu\s*$/i\
config BOEFFLA_WL_BLOCKER\
	bool "Boeffla wakelock blocker (Theettam)"\
	default n\
	help\
	  Runtime wakelock block list for qcom_rx_wakelock etc.\
' drivers/misc/Kconfig
  else
    cat >> drivers/misc/Kconfig <<'EOF'

config BOEFFLA_WL_BLOCKER
	bool "Boeffla wakelock blocker (Theettam)"
	default n
EOF
  fi
fi
grep -q boeffla_wl_blocker drivers/misc/Makefile || \
  echo 'obj-$(CONFIG_BOEFFLA_WL_BLOCKER)	+= boeffla_wl_blocker/' >> drivers/misc/Makefile

echo "[*] patches"
mkdir -p theettam/patches theettam/scripts
cp -a "$PKG/theettam/patches/." theettam/patches/
cp -a "$PKG/theettam/scripts/." theettam/scripts/
chmod +x theettam/scripts/*.sh

# wakeup hook
if [ -f kernel/power/wakeup.c ] && ! grep -q theettam_wl_should_block kernel/power/wakeup.c; then
  patch -p1 --fuzz=3 < theettam/patches/0002-wakeup-theettam-wl-block-hook.patch || \
    echo "WARN: wakeup patch fuzz — apply manually"
fi

# PELT default
if [ -f kernel/sched/pelt.c ] && grep -q 'sysctl_sched_pelt_multiplier = 1' kernel/sched/pelt.c; then
  patch -p1 --fuzz=3 < theettam/patches/0003-sched-pelt-default-8ms-half-life.patch || \
    sed -i 's/sysctl_sched_pelt_multiplier = 1/sysctl_sched_pelt_multiplier = 4/' kernel/sched/pelt.c
fi

echo "[*] done — next:"
echo "  bash theettam/scripts/integrate_root.sh ksun_susfs   # Phase 1"
echo "  bash theettam/scripts/build_theettam.sh              # build+zip"
