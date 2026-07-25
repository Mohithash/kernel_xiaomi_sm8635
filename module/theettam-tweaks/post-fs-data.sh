#!/system/bin/sh
# Theettam Tweaks — static VM + I/O sysctls, applied per PROFILE.
# All values are ordinary sysctls/queue knobs; uninstalling the module and
# rebooting restores every default. Nothing here is irreversible.

MODDIR=${0%/*}
CONF="$MODDIR/tweaks.conf"
conf() { sed -n "s/^$1=//p" "$CONF" 2>/dev/null | head -1; }

PROFILE="$(conf PROFILE)"; [ -n "$PROFILE" ] || PROFILE=balanced
[ "$(conf vmtune)" = "1" ] || exit 0

setp() { [ -w "/proc/sys/$1" ] && echo "$2" > "/proc/sys/$1" 2>/dev/null; }

# --- shared, safe on any profile ---
setp vm/page-cluster 0             # zram: single-page swapin, lower latency
setp vm/watermark_scale_factor 100 # kswapd wakes earlier -> fewer direct-reclaim stalls
setp vm/stat_interval 10           # less vmstat churn
setp vm/vfs_cache_pressure 100

# --- per-profile ---
case "$PROFILE" in
  battery)
    setp vm/swappiness 130
    setp vm/dirty_writeback_centisecs 1500   # flush less often -> fewer wakeups
    setp vm/dirty_expire_centisecs 3000
    setp vm/dirty_background_ratio 5
    setp vm/dirty_ratio 20
    RA=64 ;;
  performance)
    setp vm/swappiness 80
    setp vm/dirty_writeback_centisecs 500
    setp vm/dirty_expire_centisecs 1500
    setp vm/dirty_background_ratio 10
    setp vm/dirty_ratio 30
    RA=256 ;;
  *)  # balanced (default)
    setp vm/swappiness 100
    setp vm/dirty_writeback_centisecs 1000
    setp vm/dirty_expire_centisecs 2000
    setp vm/dirty_background_ratio 5
    setp vm/dirty_ratio 20
    RA=128 ;;
esac

# --- I/O: real storage only (skip zram/loop/dm/ram) ---
for q in /sys/block/*/queue; do
  d=$(basename "$(dirname "$q")")
  case "$d" in zram*|loop*|dm-*|ram*) continue ;; esac
  [ -w "$q/read_ahead_kb" ] && echo "$RA" > "$q/read_ahead_kb" 2>/dev/null
  [ -w "$q/iostats" ]       && echo 0    > "$q/iostats" 2>/dev/null
  [ -w "$q/nr_requests" ]   && echo 128  > "$q/nr_requests" 2>/dev/null
done
