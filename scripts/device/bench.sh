#!/system/bin/sh
# bench.sh — measure what a kernel change actually did, on the device.
#
# Companion to device-probe.sh (what is set) and postflash-check.sh (does it
# boot). This one answers "is it faster / cooler / better", which is the
# question the other two cannot. It exists because a tuning change was once
# committed here on a confident rationale that measurement later disproved:
# anything claiming a performance win should carry a number from this script.
#
#   adb push scripts/device/bench.sh /data/local/tmp/
#   adb shell su -c 'sh /data/local/tmp/bench.sh all' | tee before.txt
#   ... change something, reflash ...
#   adb shell su -c 'sh /data/local/tmp/bench.sh all' | tee after.txt
#   diff before.txt after.txt
#
# Subcommands: work | cpu | gpu | io | launch | thermal | all   (default: all)
#
# Needs root. Read-mostly: the only writes are /proc/sys/vm/drop_caches and a
# bounded temp file under /data/local/tmp, removed on exit. It does not change
# any tunable — measuring is not tuning, and a harness that edits what it
# measures is worthless.
#
# DO NOT read /sys/devices/system/cpu/cpu*/dcvsh_freq_limit from this or any
# other script on this device: a read sweep of those nodes coincided with an
# immediate hard reset (no shutdown checkpoint, empty /sys/fs/pstore,
# ro.boot.bootreason=reboot). cpuinfo_cur_freq gives the same information
# safely.
#
# Written for mksh (/system/bin/sh). mksh predefines r/type/hash/history/
# integer/local/nohup/stop/suspend as aliases, so no function may take those
# names, and its printf is an external binary, so large data is streamed rather
# than passed as one argument (a big argv fails with E2BIG).

SECS="${BENCH_SECS:-20}"          # load window per measurement
REPS="${BENCH_REPS:-5}"           # repetitions where a median is taken
TMP=/data/local/tmp/.bench.$$
cleanup() { rm -rf "$TMP" 2>/dev/null; kill $(jobs -p) 2>/dev/null; }
trap cleanup EXIT
mkdir -p "$TMP" 2>/dev/null

# mksh evaluates $(( )) in 32 bits here: a nanosecond delta above 2^31 ns
# (~2.147 s) wraps and comes back negative. Measured: a 3720 ms silver-core run
# printed -574 ms. Every ns delta therefore goes through awk, which uses
# doubles. Same class of trap as the external-printf E2BIG note above.
ms_since() { awk -v a="$1" -v b="$(date +%s%N)" 'BEGIN{printf "%d", (b-a)/1000000}'; }

say()  { printf '%-26s %s\n' "$1" "$2"; }
head2(){ echo; echo "=== $1 ==="; }
warn() { printf 'WARN  %s\n' "$1"; }

[ "$(id -u)" = 0 ] || { echo "bench.sh needs root (su -c)"; exit 1; }

# ---------------------------------------------------------------------------
# Preconditions. Each of these silently ruins a measurement if ignored, so they
# are reported at the top of every run and carried into the output file.
# ---------------------------------------------------------------------------
preconditions() {
  head2 "run conditions (these decide whether the numbers mean anything)"
  say kernel "$(uname -r)"
  say uptime "$(cut -d' ' -f1 /proc/uptime)s"

  WAKE=$(dumpsys power 2>/dev/null | grep -m1 -oE 'mWakefulness=[A-Za-z]+' | cut -d= -f2)
  say screen "${WAKE:-unknown}"
  [ "$WAKE" = Awake ] || warn "screen is not Awake: the power HAL drops GPUMaxFreq to 255 MHz on DISPLAY_INACTIVE, so GPU numbers will be meaningless"

  USB=$(cat /sys/class/power_supply/usb/online 2>/dev/null)
  BATST=$(cat /sys/class/power_supply/battery/status 2>/dev/null)
  say charging "usb_online=${USB:-?} status=${BATST:-?}"
  [ "$USB" = 1 ] && warn "phone is charging over the adb cable: battery current is not drain, power figures are omitted"

  say sensor-composite "$(tail -1 /data/vendor/thermal/thermal.dump 2>/dev/null | grep -oE 'VIRTUAL-SENSOR0 [0-9]+' | awk '{print $2}')"
  say load-cgroup "$BENCH_CGROUP (uclamp.max=$(cat $BENCH_CGROUP/cpu.uclamp.max 2>/dev/null))"
  say cpu-ceilings "policy0=$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq) policy3=$(cat /sys/devices/system/cpu/cpufreq/policy3/scaling_max_freq) policy7=$(cat /sys/devices/system/cpu/cpufreq/policy7/scaling_max_freq)"
  say gpu-ceiling "$(cat /sys/class/kgsl/kgsl-3d0/devfreq/max_freq)"
  warn "mi_thermald re-asserts these ceilings every 2000 ms from a 25 C step curve; a run is only comparable with another run at a similar composite temperature"

  # The composite mi_thermald actually steps on, recomputed from the raw zones.
  # It is NOT a CPU temperature: cpu_therm carries a negative weight, and
  # battery plus wifi_therm together carry 63% of it, so the CPU cap on this
  # phone tracks board and battery heat. Reconstructing it here lets a run say
  # how close it was to the next step before the step happens.
  VS0=$(for z in /sys/class/thermal/thermal_zone*; do
          t=$(cat $z/type 2>/dev/null); v=$(cat $z/temp 2>/dev/null)
          case "$t" in
            cpu_therm) echo "-26 $v" ;; battery) echo "301 $v" ;;
            charger_therm0) echo "147 $v" ;; wifi_therm) echo "330 $v" ;;
            pa_therm0) echo "36 $v" ;; pa_therm1) echo "119 $v" ;;
            quiet_therm) echo "-2 $v" ;;
          esac
        done | awk '{s+=$1*$2} END {if (s) printf "%d", s/1000 + 2015}')
  say composite-recomputed "${VS0:-?} mC  (next cap step at 37000)"
  [ -n "$VS0" ] && [ "$VS0" -gt 35000 ] 2>/dev/null && warn "composite is within 2 C of the 37 C step: the ceiling will very likely move mid-run"

  # Name what else is running rather than counting: this script and its own load
  # processes would otherwise count themselves and cry wolf on every run.
  OTHERS=$(ps -A -o args 2>/dev/null | grep -vE 'bench\.sh|runbench|grep|ps -A|^\[' \
           | grep -E 'stress|sysbench|monkey|simpleperf|dd if=/dev/zero' | head -3)
  [ -n "$OTHERS" ] && { warn "other load is running - numbers will be polluted:"; echo "$OTHERS" | sed 's/^/        /'; }
}

# ---------------------------------------------------------------------------
# CPU: mean sustained clock from cpufreq residency, not from sampling
# scaling_cur_freq. time_in_state is cumulative per OPP, so the delta across a
# load window gives exactly how long each frequency was actually held.
# ---------------------------------------------------------------------------
tis_snapshot() { cat "/sys/devices/system/cpu/cpufreq/policy$1/stats/time_in_state" 2>/dev/null; }

# Reproducible, tool-free CPU load: one tight ALU loop pinned per core, moved
# into top-app. That last part matters more than the loop does. An adb shell
# inherits a cgroup whose cpu.uclamp.max caps what the walt governor will even
# request — background is capped at 20% and system-background at 30% — so a
# load left where it lands measures the cgroup, not the kernel. top-app is
# uclamp.max=max. Measured on this device across a 6 s window on the gold
# cluster: inherited 1640 MHz / 29% at ceiling, top-app 1789 MHz / 39%.
BENCH_CGROUP="${BENCH_CGROUP:-/dev/cpuctl/top-app}"
LOAD_PIDS=""
cpu_load_start() {   # cpu_load_start <cpulist>
  LOAD_PIDS=""
  for c in $(echo "$1" | tr ',' ' '); do
    taskset "$(printf '%x' $((1 << c)))" sh -c 'while : ; do : ; done' >/dev/null 2>&1 &
    LOAD_PIDS="$LOAD_PIDS $!"
  done
  for p in $LOAD_PIDS; do echo "$p" > "$BENCH_CGROUP/cgroup.procs" 2>/dev/null; done
}
cpu_load_stop() { kill $LOAD_PIDS 2>/dev/null; wait 2>/dev/null; LOAD_PIDS=""; }

# Fixed work, timed. Residency says which OPP was held; this says how long real
# work took, which is the question a tuning change has to answer. One awk
# process, pure ALU, no I/O and no allocation, so it moves when the scheduler or
# an OPP limit moves and does not when only memory bandwidth changes. The first
# two iterations are discarded: they run 10-25% slow while the governor ramps.
WORK="${BENCH_WORK:-12000000}"
bench_cpu_work() {
  head2 "CPU — time to complete fixed work (${WORK} iterations, best of ${REPS} after 2 warmups)"
  echo "  cluster  cpu  best_ms  median_ms  spread_%  cap_MHz_during"
  for spec in "0:policy0" "4:policy3" "7:policy7"; do
    c=${spec%%:*}; pol=${spec#*:}
    CAP=$(cat /sys/devices/system/cpu/cpufreq/$pol/scaling_max_freq)
    : > "$TMP/work"
    I=0
    while [ $I -lt $(( REPS + 2 )) ]; do
      T0=$(date +%s%N)
      taskset "$(printf '%x' $((1 << c)))" awk -v n="$WORK" 'BEGIN{x=0;for(i=0;i<n;i++)x=x+i}' >/dev/null 2>&1
      [ $I -ge 2 ] && ms_since "$T0" >> "$TMP/work" && echo >> "$TMP/work"   # discard 2 warmups
      I=$(( I + 1 ))
    done
    CAP2=$(cat /sys/devices/system/cpu/cpufreq/$pol/scaling_max_freq)
    sort -n "$TMP/work" | awk -v pol="$pol" -v c="$c" -v cap="$CAP" -v cap2="$CAP2" '
      {v[NR]=$1} END {
        if (NR==0) { printf "  %-7s  %-3s  (no timings)\n", pol, c; exit }
        printf "  %-7s  %-3s  %-7d  %-9d  %-8.1f  %s\n", pol, c, v[1], v[int((NR+1)/2)],
               (v[1]>0 ? 100*(v[NR]-v[1])/v[1] : 0),
               (cap==cap2 ? cap/1000 : cap/1000 "->" cap2/1000 " STEPPED")
      }'
  done
  echo "  lower ms is faster. spread_% is (max-min)/min: above ~10% the run was disturbed"
}

bench_cpu() {
  head2 "CPU — mean sustained clock under load (${SECS}s per cluster)"
  echo "  cluster  mean_MHz  peak_MHz  ceiling_MHz  %_at_ceiling  throttled_during_run"
  for spec in "0:0,1,2:policy0" "3:3,4,5,6:policy3" "7:7:policy7"; do
    cpu=${spec%%:*}; rest=${spec#*:}; cpus=${rest%%:*}; pol=${rest#*:}
    P=${pol#policy}
    CEIL0=$(cat /sys/devices/system/cpu/cpufreq/$pol/scaling_max_freq)
    tis_snapshot "$P" > "$TMP/tis.a"
    cpu_load_start "$cpus"
    sleep "$SECS"
    cpu_load_stop
    tis_snapshot "$P" > "$TMP/tis.b"
    CEIL1=$(cat /sys/devices/system/cpu/cpufreq/$pol/scaling_max_freq)

    # Join the two snapshots on frequency and weight each OPP by its delta.
    awk -v ceil="$CEIL0" '
      NR==FNR { a[$1]=$2; next }
      { d=$2-a[$1]; if (d>0) { tot+=d; sum+=$1*d; if ($1>peak) peak=$1; if ($1>=ceil) atc+=d } }
      END {
        if (tot<=0) { printf "  %-8s  (no residency delta - load did not land)\n", ceil; exit }
        printf "  %-7s  %-8.0f  %-8.0f  %-11.0f  %-12.1f  %s\n", pol, sum/tot/1000, peak/1000, ceil/1000, 100*atc/tot, thr
      }' pol="$pol" thr="$([ "$CEIL0" = "$CEIL1" ] && echo no || echo "YES $CEIL0->$CEIL1")" \
      "$TMP/tis.a" "$TMP/tis.b"
  done
  echo "  (mean_MHz is residency-weighted: sum(freq*ticks)/sum(ticks) across the window)"
  echo "  load ran in $BENCH_CGROUP; these are COMPARISON numbers, not peak-capability numbers -"
  echo "  a shell loop does not saturate the big clusters, so only compare runs made the same way"
}

# ---------------------------------------------------------------------------
# GPU: same idea. devfreq trans_stat carries per-OPP residency in ms.
# ---------------------------------------------------------------------------
bench_gpu() {
  head2 "GPU — clock residency under UI load (${SECS}s)"
  D=/sys/class/kgsl/kgsl-3d0
  # Re-assert here rather than trusting the $WAKE read from preconditions: in a
  # full run this section starts minutes later, and a baseline once measured the
  # GPU entirely at 255 MHz with 0% busy because the display had gone inactive
  # in between. The ceiling itself is the reliable tell - DISPLAY_INACTIVE pins
  # GPUMaxFreq to 255000000 - so check that, not just wakefulness.
  input keyevent KEYCODE_WAKEUP >/dev/null 2>&1
  sleep 2
  CEIL=$(cat $D/devfreq/max_freq)
  if [ "$CEIL" = 255000000 ]; then
    echo "  SKIPPED: GPUMaxFreq is pinned at 255 MHz (DISPLAY_INACTIVE)."
    echo "  The display went inactive before this section started. Raise"
    echo "  screen_off_timeout for the whole run, or measure with: bench.sh gpu"
    return
  fi
  cat $D/devfreq/trans_stat > "$TMP/gs.a" 2>/dev/null

  # UI load without installing anything: repeated scrolls on the launcher.
  ( END=$(( $(cut -d. -f1 /proc/uptime) + SECS ))
    while [ "$(cut -d. -f1 /proc/uptime)" -lt "$END" ]; do
      input swipe 540 1800 540 600 120 >/dev/null 2>&1
    done ) &
  LOADER=$!
  BUSY=0; N=0
  while kill -0 $LOADER 2>/dev/null; do
    B=$(cat $D/gpu_busy_percentage 2>/dev/null | tr -dc '0-9')
    BUSY=$(( BUSY + ${B:-0} )); N=$(( N + 1 ))
  done
  wait $LOADER 2>/dev/null
  cat $D/devfreq/trans_stat > "$TMP/gs.b" 2>/dev/null

  say ceiling_MHz "$(( CEIL / 1000000 ))"
  say mean_busy_pct "$(( N > 0 ? BUSY / N : 0 ))  (${N} samples)"
  # trans_stat rows are "<freq>: <matrix...> <time_ms>", except the row for the
  # CURRENT frequency, which devfreq prefixes with '*'. That shifts every field
  # by one, so keying on $1 alone yields the key "*": the before/after keys stop
  # matching and the delta comes back as the whole cumulative total. A 20 s
  # window once reported 3337960 ms this way.
  awk '
    function freq(  f) { f = ($1 == "*") ? $2 : $1; sub(":", "", f); return f }
    /From|time\(ms\)|Total transition/ { next }
    $0 !~ /[0-9]:/ { next }
    NR==FNR { a[freq()] = $NF; next }
    { f = freq(); d = $NF - a[f]
      if (d > 0) { tot += d; printf "  %-12s %8d ms\n", f/1000000 " MHz", d } }
    END { if (tot > 0) printf "  %-12s %8d ms in the window\n", "total", tot
          else print "  (no GPU residency delta - the load never reached the GPU)" }
  ' "$TMP/gs.a" "$TMP/gs.b"
}

# ---------------------------------------------------------------------------
# I/O: read throughput on an existing file with the page cache dropped, which
# is the honest way to compare scheduler tunables without writing to flash.
# A small bounded write is offered separately and cleaned up.
# ---------------------------------------------------------------------------
bench_io() {
  head2 "storage I/O (/data is $(grep ' /data ' /proc/mounts | cut -d' ' -f1))"
  DM=$(grep ' /data ' /proc/mounts | cut -d' ' -f1 | sed 's|/dev/block/||')
  say scheduler "$(cat /sys/block/sda/queue/scheduler 2>/dev/null)"
  say nr_requests "$(cat /sys/block/sda/queue/nr_requests 2>/dev/null)"
  say read_ahead_kb "$(cat /sys/block/sda/queue/read_ahead_kb 2>/dev/null)"

  # Pick an existing large file so the read test writes nothing.
  SRC=$(ls -S /data/app/*/*/base.apk /data/app/*/base.apk 2>/dev/null | head -1)
  [ -z "$SRC" ] && SRC=$(ls -S /system/app/*/*.apk 2>/dev/null | head -1)
  if [ -z "$SRC" ]; then echo "  no large file found to read; skipped"; return; fi
  SZ=$(( $(stat -c %s "$SRC" 2>/dev/null || echo 0) / 1048576 ))
  say read_source "$SRC (${SZ} MiB)"

  I=0; BEST=0
  while [ $I -lt "$REPS" ]; do
    sync; echo 3 > /proc/sys/vm/drop_caches
    T0=$(date +%s%N)
    dd if="$SRC" of=/dev/null bs=1M >/dev/null 2>&1
    MS=$(ms_since "$T0")
    [ "$MS" -gt 0 ] && R=$(( SZ * 1000 / MS )) || R=0
    echo "  run $((I+1)): ${MS} ms  ${R} MB/s"
    [ "$R" -gt "$BEST" ] && BEST=$R
    I=$(( I + 1 ))
  done
  say best_read "${BEST} MB/s (cold cache each run)"
  say dm_stat_reads "$(awk '{print $1" reads, "$5" writes"}' /sys/block/$DM/stat 2>/dev/null)"
}

# ---------------------------------------------------------------------------
# Launch latency: cold start, median of REPS. am start -W reports TotalTime
# only for a genuinely cold start, so force-stop first.
# ---------------------------------------------------------------------------
bench_launch() {
  head2 "app cold-start latency (median of ${REPS})"
  for PKG in com.android.settings/.Settings com.android.deskclock/.DeskClock; do
    P=${PKG%%/*}
    pm list packages 2>/dev/null | grep -q "^package:$P$" || continue
    : > "$TMP/launch"
    I=0
    while [ $I -lt "$REPS" ]; do
      am force-stop "$P" 2>/dev/null; sleep 1
      T=$(am start -W -n "$PKG" 2>/dev/null | grep -m1 '^TotalTime:' | awk '{print $2}')
      [ -n "$T" ] && echo "$T" >> "$TMP/launch"
      am force-stop "$P" 2>/dev/null
      I=$(( I + 1 ))
    done
    input keyevent KEYCODE_HOME >/dev/null 2>&1
    if [ -s "$TMP/launch" ]; then
      say "$P" "$(sort -n "$TMP/launch" | awk '{v[NR]=$1} END {printf "median %d ms   (runs: ", v[int((NR+1)/2)]; for(i=1;i<=NR;i++) printf "%s ", v[i]; print ")"}')"
    else
      say "$P" "no TotalTime reported"
    fi
  done
}

# ---------------------------------------------------------------------------
# Thermal: which zones moved, and whether mi_thermald stepped mid-run — the
# single most common reason two runs disagree.
# ---------------------------------------------------------------------------
bench_thermal() {
  head2 "thermal state"
  for z in /sys/class/thermal/thermal_zone*; do
    t=$(cat $z/type 2>/dev/null)
    case "$t" in gpuss-0|cpu-1-0|quiet_therm|battery|skin*|*therm0)
      printf '  %-16s %s mC\n' "$t" "$(cat $z/temp 2>/dev/null)" ;;
    esac
  done
  say composite "$(tail -1 /data/vendor/thermal/thermal.dump 2>/dev/null | grep -oE 'VIRTUAL-SENSOR0 [0-9]+' | awk '{print $2}') (mi_thermald step input)"
  say gpu_cdev_state "$(cat /sys/class/thermal/cooling_device37/cur_state 2>/dev/null) of $(cat /sys/class/thermal/cooling_device37/max_state 2>/dev/null)"
}

case "${1:-all}" in
  cpu)     preconditions; bench_cpu ;;
  gpu)     preconditions; bench_gpu ;;
  io)      preconditions; bench_io ;;
  launch)  preconditions; bench_launch ;;
  thermal) preconditions; bench_thermal ;;
  work)    preconditions; bench_cpu_work ;;
  all)     preconditions; bench_thermal; bench_cpu_work; bench_cpu; bench_gpu; bench_io; bench_launch; bench_thermal ;;
  *)       echo "usage: bench.sh [work|cpu|gpu|io|launch|thermal|all]"; exit 2 ;;
esac
echo
echo "=== done: $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
