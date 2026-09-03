#!/system/bin/sh
# device-probe.sh — read-only on-device state dump, before any tuning decision.
#
# Answers questions the tree cannot answer from a build box: which I/O
# scheduler and cpuidle governor are actually live, whether MTE/KASAN is
# exposed, whether DAMON/LRU-sort are enabled at runtime, current f2fs/zram
# settings. Never writes anything. Run as root (su -c) via adb shell, or push
# and run directly on device:
#
#   adb push scripts/device/device-probe.sh /data/local/tmp/
#   adb shell su -c 'sh /data/local/tmp/device-probe.sh' > device-probe.txt
#
# POSIX sh only (Android's toolbox/toybox shell), every read guarded so a
# missing node just skips instead of aborting the whole dump.

# Named rd, not r: mksh (Android's /system/bin/sh) predefines r as an alias for
# 'fc -e -', which silently swallows a function called r.
rd() { [ -r "$1" ] && { printf '%s: ' "$1"; cat "$1" 2>/dev/null; } || echo "$1: (absent)"; }

echo "=== kernel ==="
rd /proc/version
rd /proc/cmdline
uname -r

echo
echo "=== storage: block device + scheduler ==="
for d in /sys/block/sd*/queue /sys/block/mmcblk*/queue; do
  [ -d "$d" ] || continue
  dev=$(dirname "$d" | xargs basename)
  echo "-- $dev --"
  rd "$d/scheduler"
  rd "$d/nr_requests"
  rd "$d/read_ahead_kb"
  rd "$d/rq_affinity"
  echo "hw queues: $(ls "$d/../mq" 2>/dev/null | wc -l)"
  if [ -d "$d/iosched" ]; then
    for f in "$d"/iosched/*; do rd "$f"; done
  fi
done

echo
echo "=== zram ==="
for z in /sys/block/zram*; do
  [ -d "$z" ] || continue
  echo "-- $(basename "$z") --"
  rd "$z/comp_algorithm"
  rd "$z/disksize"
  rd "$z/backing_dev"
  rd "$z/mm_stat"
done

echo
echo "=== vm ==="
rd /proc/sys/vm/swappiness
rd /proc/sys/vm/page-cluster
rd /proc/sys/vm/watermark_scale_factor
rd /proc/sys/vm/watermark_boost_factor
rd /proc/sys/vm/min_free_kbytes

echo
echo "=== MGLRU / THP / DAMON ==="
rd /sys/kernel/mm/lru_gen/enabled
rd /sys/kernel/mm/lru_gen/min_ttl_ms
rd /sys/kernel/mm/transparent_hugepage/enabled
rd /sys/kernel/mm/transparent_hugepage/defrag
rd /sys/kernel/mm/transparent_hugepage/khugepaged/defrag
rd /sys/module/damon_reclaim/parameters/enabled
rd /sys/module/damon_lru_sort/parameters/enabled

echo
echo "=== cpuidle governor ==="
rd /sys/devices/system/cpu/cpuidle/current_governor_ro
rd /sys/devices/system/cpu/cpuidle/available_governors
echo "vendor lpm module loaded: $(lsmod 2>/dev/null | grep -c lpm)"

echo
echo "=== cpufreq governor (per policy) ==="
for p in /sys/devices/system/cpu/cpufreq/policy*; do
  [ -d "$p" ] || continue
  echo "-- $(basename "$p") --"
  rd "$p/scaling_governor"
  rd "$p/scaling_cur_freq"
done

echo
echo "=== MTE / KASAN ==="
dmesg 2>/dev/null | grep -iE 'kasan|mte' | head -5
grep -m1 -E 'mte' /proc/cpuinfo 2>/dev/null || echo "mte: not in /proc/cpuinfo"

echo
echo "=== memory ==="
grep -E '^(Slab|SUnreclaim|SwapTotal|SwapFree):' /proc/meminfo 2>/dev/null

echo
echo "=== f2fs ==="
for f in /sys/fs/f2fs/*/; do
  [ -d "$f" ] || continue
  echo "-- $(basename "$f") --"
  rd "${f}gc_urgent_sleep_time"
  rd "${f}gc_idle"
  rd "${f}gc_urgent"
done
grep ' /data ' /proc/mounts 2>/dev/null

echo
echo "=== watchdog / softlockup ==="
rd /proc/sys/kernel/watchdog_thresh
rd /proc/sys/kernel/soft_watchdog

echo
echo "=== hardening sysctls (root-only on Android; BOOT-NOTES Rule 11 BPF_UNPRIV_DEFAULT_OFF question) ==="
rd /proc/sys/kernel/unprivileged_bpf_disabled
rd /proc/sys/kernel/kptr_restrict
rd /proc/sys/kernel/dmesg_restrict
rd /proc/sys/net/core/bpf_jit_harden

echo
echo "=== suspend ==="
rd /sys/power/sync_on_suspend

echo
echo "=== done: $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
