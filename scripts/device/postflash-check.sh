#!/system/bin/sh
# postflash-check.sh — post-flash sanity check, run ON THE DEVICE (companion to
# scripts/device/device-probe.sh, same invocation style). Never writes anything.
#
# Prints PASS/FAIL/SKIP/INFO for each check plus a final verdict line, and exits
# 0 (all PASS/SKIP/INFO) or 1 (>=1 FAIL) so it is usable as a gate over adb, not
# just eyeballed. Root is opportunistic: run it as plain shell or already inside
# `su -c`; it self-detects and escalates only the reads that need it. A check
# that needs root and does not have it SKIPs instead of FAILing.
#
#   adb push scripts/device/postflash-check.sh /data/local/tmp/
#   adb shell sh /data/local/tmp/postflash-check.sh [expected-kernel-release] [flavor] \
#     | tee postflash-report.txt; echo "exit=$?"
#
# expected-kernel-release: the `uname -r` this build should report, i.e.
#   `cat out/include/config/kernel.release` after scripts/ci/build-flavor.sh, or
#   the release string in the zip name. Omit it and the check degrades to a
#   self-consistency check (uname -r found in /proc/version).
#
# flavor: one of scripts/ci/build-flavor.sh's names (plain ksun-plain ksun-susfs
#   sukisu-susfs ksun-susfs-droidspaces resukisu-susfs premium apatch). Gates
#   the SUSFS and DroidSpaces checks; omit it and both SKIP as "not asserted".
#
# Written for mksh (Android's /system/bin/sh): no function may be called r,
# type, hash, history, integer, local, nohup, stop or suspend (predefined
# aliases); every read is guarded so a missing node fails only its own check.

PASS=0; FAIL=0; SKIP=0; INFO=0; FAILED=""
pass() { PASS=$((PASS + 1)); printf 'PASS  %-22s %s\n' "$1" "$2"; }
fail() { FAIL=$((FAIL + 1)); FAILED="$FAILED $1"; printf 'FAIL  %-22s %s\n' "$1" "$2"; }
skip() { SKIP=$((SKIP + 1)); printf 'SKIP  %-22s %s\n' "$1" "$2"; }
info() { INFO=$((INFO + 1)); printf 'INFO  %-22s %s\n' "$1" "$2"; }

EXPECT_REL="${1:-}"
FLAVOR="${2:-}"

echo "=== postflash-check: $(date -u +%Y-%m-%dT%H:%M:%SZ) flavor=${FLAVOR:-unset} ==="

# ---- root: opportunistic, per check ------------------------------------------
AM_ROOT=0; CAN_SU=0
[ "$(id -u 2>/dev/null)" = "0" ] && AM_ROOT=1
if [ "$AM_ROOT" = 0 ] && command -v su >/dev/null 2>&1; then
  case "$(su -c id 2>/dev/null)" in *uid=0*) CAN_SU=1 ;; esac
fi
HAVE_ROOT=0
if [ "$AM_ROOT" = 1 ] || [ "$CAN_SU" = 1 ]; then HAVE_ROOT=1; fi
priv() {
  # Run "$@" with whatever root we have. Caller checks HAVE_ROOT first.
  if [ "$AM_ROOT" = 1 ]; then "$@"; else su -c "$*"; fi
}
if [ "$HAVE_ROOT" = 1 ]; then
  if [ "$AM_ROOT" = 1 ]; then info root "invoked as root"; else info root "available via su -c"; fi
else
  info root "unavailable (plain flavor, or the manager app has not granted shell) - root-gated checks SKIP"
fi

# ==============================================================================
# 1. kernel release
# ==============================================================================
ACTUAL_REL="$(uname -r 2>/dev/null)"
PROCVER="$(cat /proc/version 2>/dev/null)"
if [ -z "$ACTUAL_REL" ]; then
  fail kernel-release "uname -r returned nothing"
elif [ -n "$EXPECT_REL" ]; then
  if [ "$ACTUAL_REL" = "$EXPECT_REL" ]; then
    pass kernel-release "$ACTUAL_REL"
  else
    fail kernel-release "got '$ACTUAL_REL', expected '$EXPECT_REL'"
  fi
else
  case "$PROCVER" in
    *"$ACTUAL_REL"*) pass kernel-release "$ACTUAL_REL (self-consistent with /proc/version; pass the expected release as arg1 for a real compare)" ;;
    *) fail kernel-release "uname -r='$ACTUAL_REL' not found in /proc/version" ;;
  esac
fi
info proc-version "$PROCVER"

# ==============================================================================
# 2. /proc/config.gz present and scrubbed of CONFIG_KSU/KPM/SUSFS
#    (HIDING.md; kernel/Makefile filechk_ikconfig scrubs every flavor, so this
#    needs no root and must hold on root and no-root builds alike)
# ==============================================================================
# The decompressed config is ~250 KB: never hold it in a variable (mksh's
# printf is external, and one argument that size fails with E2BIG, which would
# turn this into a silent PASS on an empty stream). Stream it every time.
cfg() { gzip -dc /proc/config.gz 2>/dev/null || gunzip -c /proc/config.gz 2>/dev/null || zcat /proc/config.gz 2>/dev/null; }
NCFG="$(cfg | wc -l | tr -d ' ')"
if [ "${NCFG:-0}" -lt 1000 ] 2>/dev/null; then
  fail config-gz-present "/proc/config.gz missing or unreadable (${NCFG:-0} lines; system_server reads it, CONFIG_IKCONFIG_PROC must stay on, HIDING.md)"
else
  LEAK="$(cfg | grep -E 'CONFIG_(KSU|KPM)[_= ]|KernelSU|SUSFS|kernelsu' | head -1)"
  if [ -z "$LEAK" ]; then
    pass config-gz-scrubbed "$NCFG lines, no CONFIG_KSU*/CONFIG_KPM*/SUSFS/KernelSU lines"
  else
    fail config-gz-scrubbed "leaking, e.g.: $LEAK"
  fi
fi

# ==============================================================================
# 3. dmesg: boot-killer / instability lines (root: dmesg_restrict)
#    Hard failures always FAIL. A kernel WARN_ON ('WARNING: CPU:') FAILs unless
#    its site is in KNOWN_WARN, the stock vendor-module warnings peridot prints
#    on every boot (docs/BOOT-NOTES.md Rule 10 boot record):
#      drivers/spmi/spmi-pmic-arb.c:309  qcom_spmi_pmic probing an absent PMIC address
#      kernel/irq/manage.c:914           goodix_ts gesture resume, unbalanced IRQ wake
# ==============================================================================
# Case-sensitive on purpose: 'ramoops_region' and 'debug' must not match Oops/BUG.
HARD='disagrees about version|module verification failed|exec format error|Kernel panic|[^a-zA-Z_]BUG: |blocked for more than|soft lockup|detected stalls? on CPU|Internal error: Oops'
KNOWN_WARN='drivers/spmi/spmi-pmic-arb.c:309 kernel/irq/manage.c:914'
# Same rule as config.gz: the ring buffer is up to log_buf_len=2M, so stream it.
dm() { priv dmesg 2>/dev/null; }
if [ "$HAVE_ROOT" = 1 ]; then
  NDM="$(dm | wc -l | tr -d ' ')"
  if [ "${NDM:-0}" -lt 50 ] 2>/dev/null; then
    skip dmesg-clean "dmesg returned ${NDM:-0} lines (ring buffer rotated? re-run right after boot)"
  else
    NH="$(dm | grep -cE "$HARD" | tr -d ' ')"
    UNKNOWN=""; KNOWN=""
    for site in $(dm | grep -oE 'WARNING: CPU: [0-9]+ PID: [0-9]+ at [^ ]+' | awk '{print $NF}' | sort -u); do
      case " $KNOWN_WARN " in
        *" $site "*) KNOWN="$KNOWN $site" ;;
        *) UNKNOWN="$UNKNOWN $site" ;;
      esac
    done
    if [ "${NH:-1}" -eq 0 ] 2>/dev/null && [ -z "$UNKNOWN" ]; then
      pass dmesg-clean "$NDM lines, 0 hard failures, no unexpected WARN_ON${KNOWN:+ (known vendor WARNs:$KNOWN)}"
    elif [ "${NH:-1}" -gt 0 ] 2>/dev/null; then
      fail dmesg-clean "$NH hard-failure line(s), first: $(dm | grep -E "$HARD" | head -1)"
    else
      fail dmesg-clean "unexpected WARN_ON site(s):$UNKNOWN (known:${KNOWN:- none})"
    fi
    if dm | grep -q 'Unprivileged eBPF is enabled'; then
      info unpriv-bpf "kernel warns 'Unprivileged eBPF is enabled' (unprivileged_bpf_disabled=0): CONFIG_BPF_UNPRIV_DEFAULT_OFF not in effect"
    fi
  fi
else
  skip dmesg-clean "no root: dmesg_restrict blocks the unprivileged read"
fi

# ==============================================================================
# 4. lsmod: vendor module count + the load-bearing ones
#    (peridot names verified 2026-09-03: msm_drm msm_kgsl rmnet_shs
#     qca_cld3_qca6750 xiaomi_touch; the wifi module carries a chip suffix)
# ==============================================================================
LSMOD="$(lsmod 2>/dev/null)"
if [ -z "$LSMOD" ]; then
  fail lsmod-count "lsmod returned nothing"
else
  N="$(printf '%s\n' "$LSMOD" | grep -vciE '^(module[[:space:]]+size|tainted:)')"
  if [ "${N:-0}" -ge 400 ] 2>/dev/null; then
    pass lsmod-count "$N modules loaded (>= 400; stock peridot loads ~445)"
  else
    fail lsmod-count "only $N modules loaded (< 400: vendor_dlkm modules refusing to load is the KABI-CRC bootloop signature, docs/BOOT-NOTES.md Rule 1)"
  fi
  MISS=""
  for m in msm_drm msm_kgsl rmnet_shs qca_cld3 xiaomi_touch; do
    printf '%s\n' "$LSMOD" | grep -qE "^$m[a-z0-9_]* " || MISS="$MISS $m"
  done
  if [ -z "$MISS" ]; then
    pass lsmod-critical "display, GPU, rmnet, wifi, touch modules loaded"
  else
    fail lsmod-critical "missing:$MISS"
  fi
fi

# ==============================================================================
# 5. SELinux enforcing (HIDING.md: nothing in this tree fakes it)
# ==============================================================================
ENF="$(getenforce 2>/dev/null)"
if [ "$ENF" = "Enforcing" ]; then
  pass selinux "Enforcing"
else
  fail selinux "getenforce='$ENF' (expected Enforcing)"
fi

# ==============================================================================
# 6. telephony: voice/data registration + IMS (SKIPs with no SIM)
# ==============================================================================
SIMSTATE="$(getprop gsm.sim.state 2>/dev/null)"
case "$SIMSTATE" in
  *READY*|*LOADED*) HAVE_SIM=1 ;;
  *) HAVE_SIM=0 ;;
esac
if [ "$HAVE_SIM" = 0 ]; then
  skip telephony-reg "no SIM (gsm.sim.state='${SIMSTATE:-unset}'): insert one to test registration and VoLTE"
  skip telephony-ims "no SIM"
else
  TEL="$(dumpsys telephony.registry 2>/dev/null)"
  if [ -z "$TEL" ]; then
    skip telephony-reg "dumpsys telephony.registry returned nothing"
    skip telephony-ims "dumpsys telephony.registry returned nothing"
  else
    V="$(printf '%s\n' "$TEL" | grep -oE 'mVoiceRegState=[0-9]+' | head -1)"
    D="$(printf '%s\n' "$TEL" | grep -oE 'mDataRegState=[0-9]+' | head -1)"
    if [ "$V" = "mVoiceRegState=0" ] && [ "$D" = "mDataRegState=0" ]; then
      pass telephony-reg "voice+data IN_SERVICE ($V $D)"
    else
      fail telephony-reg "voice='${V:-not found}' data='${D:-not found}' (expected =0 / IN_SERVICE with a SIM present)"
    fi
    IMS="$(printf '%s\n' "$TEL" | grep -iE 'mImsReg|ImsRegistrationState|imsRadioTech' | head -2)"
    if [ -n "$IMS" ]; then
      case "$IMS" in
        *true*|*REGISTERED*) pass telephony-ims "$(printf '%s\n' "$IMS" | head -1)" ;;
        *) fail telephony-ims "IMS field present but not registered: $(printf '%s\n' "$IMS" | head -1)" ;;
      esac
    else
      skip telephony-ims "no IMS field in dumpsys telephony.registry (name varies by ROM): do the real VoLTE call, docs/RELEASE-CHECKLIST.md step 3"
    fi
  fi
fi

# ==============================================================================
# 7. wifi / bluetooth switched on (a FAIL here is fine if you turned them off)
# ==============================================================================
W="$(settings get global wifi_on 2>/dev/null)"
B="$(settings get global bluetooth_on 2>/dev/null)"
if [ "$W" = "1" ]; then pass wifi-on "wifi_on=1"; else fail wifi-on "settings get global wifi_on='$W' (expected 1)"; fi
if [ "$B" = "1" ]; then pass bt-on "bluetooth_on=1"; else fail bt-on "settings get global bluetooth_on='$B' (expected 1)"; fi

# ==============================================================================
# 8. fingerprint HAL registered
# ==============================================================================
FP="$(service list 2>/dev/null | grep -i fingerprint)"
if [ -n "$FP" ]; then
  pass fingerprint-hal "$(printf '%s\n' "$FP" | head -1 | sed 's/^[[:space:]]*//')"
else
  fail fingerprint-hal "no fingerprint service in 'service list' (peridot has a side sensor; this must not be empty)"
fi

# ==============================================================================
# 9. thermal zones present
# ==============================================================================
TZ="$(ls -d /sys/class/thermal/thermal_zone*/temp 2>/dev/null | wc -l)"
if [ "${TZ:-0}" -gt 0 ] 2>/dev/null; then
  pass thermal-zones "$TZ thermal_zone*/temp nodes (peridot exposes ~75)"
else
  fail thermal-zones "no /sys/class/thermal/thermal_zone*/temp nodes"
fi

# ==============================================================================
# 10. report only: cpuidle governor, I/O scheduler, HZ (tuning data, not a gate)
# ==============================================================================
CPG="$(cat /sys/devices/system/cpu/cpuidle/current_governor_ro 2>/dev/null)"
info cpuidle-governor "${CPG:-(node absent)}"
IOS=""
if [ "$HAVE_ROOT" = 1 ]; then
  IOS="$(priv cat /sys/block/sda/queue/scheduler 2>/dev/null)"
  info io-scheduler "${IOS:-(no /sys/block/sda/queue/scheduler)}"
else
  info io-scheduler "(root needed to read /sys/block/sda/queue/scheduler on Android)"
fi
HZL="$(cfg | grep '^CONFIG_HZ=' | head -1)"
info kernel-hz "${HZL:-(CONFIG_HZ not in config.gz)}"
# Hardening sysctls Android keeps root-only; the values decide whether the
# CONFIG_BPF_UNPRIV_DEFAULT_OFF question in docs/BOOT-NOTES.md needs a change.
if [ "$HAVE_ROOT" = 1 ]; then
  HS=""
  for f in kernel/unprivileged_bpf_disabled kernel/kptr_restrict kernel/dmesg_restrict kernel/perf_event_paranoid fs/protected_symlinks fs/protected_hardlinks net/core/bpf_jit_harden; do
    HS="$HS ${f#*/}=$(priv cat /proc/sys/$f 2>/dev/null || echo '?')"
  done
  info hardening-sysctls "$HS"
else
  skip hardening-sysctls "no root: /proc/sys/kernel/{unprivileged_bpf_disabled,kptr_restrict,...} are root-only on Android"
fi

# ==============================================================================
# 11. report only: KSU driver presence, best effort (config.gz is scrubbed, so
#     the manager app is the authority on the driver version)
# ==============================================================================
KSUD=/data/adb/ksu/bin/ksud
if [ "$HAVE_ROOT" = 1 ]; then
  if priv test -e "$KSUD"; then
    info ksu-driver "ksud present at $KSUD (confirm the driver version in the manager app)"
  else
    info ksu-driver "no $KSUD (plain/apatch flavor, or the manager app never ran)"
  fi
else
  skip ksu-driver "no root: cannot probe /data/adb/ksu"
fi

# ==============================================================================
# 12. SUSFS evidence, asserted only when arg2 names a SUSFS flavor
# ==============================================================================
case "$FLAVOR" in
  ksun-susfs|sukisu-susfs|ksun-susfs-droidspaces|resukisu-susfs|premium)
    if [ "$HAVE_ROOT" = 1 ]; then
      SD="$(priv dmesg 2>/dev/null | grep -ic susfs)"
      SDIR=no; priv test -d /data/adb/ksu && SDIR=yes
      if [ "${SD:-0}" -gt 0 ] 2>/dev/null; then
        pass susfs-evidence "$SD susfs dmesg line(s) (flavor=$FLAVOR)"
      elif [ "$SDIR" = yes ]; then
        skip susfs-evidence "no susfs dmesg line (ring buffer rotated?) but /data/adb/ksu exists: confirm in the manager app's SUSFS page"
      else
        fail susfs-evidence "flavor=$FLAVOR expects SUSFS but no dmesg 'susfs' line and no /data/adb/ksu"
      fi
    else
      skip susfs-evidence "no root: confirm in the manager app's SUSFS page"
    fi
    ;;
  "") skip susfs-evidence "no flavor given (arg2)" ;;
  *)  skip susfs-evidence "flavor=$FLAVOR has no SUSFS (not asserted)" ;;
esac

# ==============================================================================
# 13. DroidSpaces namespaces, asserted only for the two DroidSpaces flavors
#     (scripts/droidspaces/droidspaces.config: PID_NS, USER_NS, IPC_NS, SYSVIPC;
#      a non-DroidSpaces Image shows only ipc/mnt/net/uts/cgroup/time here)
# ==============================================================================
case "$FLAVOR" in
  ksun-susfs-droidspaces|premium)
    NS="$(ls -1 /proc/self/ns/ 2>/dev/null)"
    MISS=""
    for n in pid user ipc; do
      printf '%s\n' "$NS" | grep -qx "$n" || MISS="$MISS $n"
    done
    if [ -z "$MISS" ] && [ -n "$NS" ]; then
      pass droidspaces-ns "pid/user/ipc present in /proc/self/ns"
    else
      fail droidspaces-ns "missing from /proc/self/ns:$MISS (flavor=$FLAVOR needs CONFIG_PID_NS/USER_NS/IPC_NS)"
    fi
    SV="$(ls -1 /proc/sysvipc/ 2>/dev/null)"
    if [ -n "$SV" ]; then
      pass droidspaces-sysvipc "/proc/sysvipc present ($(printf '%s\n' "$SV" | tr '\n' ' '))"
    else
      fail droidspaces-sysvipc "/proc/sysvipc missing (CONFIG_SYSVIPC not active; scripts/droidspaces/integrate.sh's KABI-reserve relocation exists for this)"
    fi
    ;;
  "")
    skip droidspaces-ns "no flavor given (arg2)"
    skip droidspaces-sysvipc "no flavor given (arg2)"
    ;;
  *)
    skip droidspaces-ns "flavor=$FLAVOR is not a DroidSpaces flavor (not asserted)"
    skip droidspaces-sysvipc "flavor=$FLAVOR is not a DroidSpaces flavor (not asserted)"
    ;;
esac

# ==============================================================================
# verdict
# ==============================================================================
echo "----------------------------------------------------------------"
echo "PASS=$PASS FAIL=$FAIL SKIP=$SKIP INFO=$INFO"
if [ "$FAIL" -eq 0 ]; then
  echo "VERDICT: PASS"
  exit 0
else
  echo "VERDICT: FAIL ($FAIL failing check(s):$FAILED)"
  exit 1
fi
