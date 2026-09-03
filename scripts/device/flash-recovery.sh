#!/bin/bash
# flash-recovery.sh — flash an AnyKernel3 zip through OrangeFox/TWRP over adb,
# unattended, from the build box; then wait for Android and print the result.
#
#   scripts/device/flash-recovery.sh dist/Theettam-<flavor>-...zip [flavor]
#
# Needs: a phone with a TWRP-derived recovery that exposes a root adb shell
# (OrangeFox does), USB debugging on, and adb reachable (over an SSH reverse
# tunnel, set ADB_SERVER_SOCKET=tcp:127.0.0.1:<port>). The zip goes to the
# recovery's tmpfs, not /sdcard, so it works with /data still encrypted.
#
# It reboots the phone twice. It does not back anything up: take a boot
# partition image first if you want a fastboot-flashable rollback
#   adb shell su -c 'dd if=/dev/block/by-name/boot_$(getprop ro.boot.slot_suffix | tr -d _) of=/data/local/tmp/boot.img'
# (root needed; on a no-root flavor use the recovery shell instead).
set -euo pipefail
ZIP="${1:?zip path}"; FLAVOR="${2:-}"
[ -f "$ZIP" ] || { echo "no such zip: $ZIP" >&2; exit 1; }
REL="$(basename "$ZIP" | grep -oE '6\.1\.[0-9]+-android14-[0-9]+-g[0-9a-f]+-ab[0-9]+' || true)"

say(){ printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }
state(){ adb devices -l 2>/dev/null | awk 'NR>1 && NF {print $2; exit}'; }
wait_for(){  # wait_for <state> <seconds>
  local want="$1" max="$2" i=0 s
  while [ $i -lt "$max" ]; do
    s="$(state || true)"
    [ "$s" = offline ] && adb reconnect offline >/dev/null 2>&1 || true
    [ "$s" = "$want" ] && return 0
    sleep 5; i=$((i+5))
  done
  echo "timed out waiting for adb state '$want' (last: '${s:-none}')" >&2; return 1
}

say "device: $(state || echo none)"
if [ "$(state)" != recovery ]; then
  say "rebooting to recovery"
  adb reboot recovery
  sleep 10
  wait_for recovery 180
fi
say "recovery shell: $(adb shell 'id -u; getprop ro.product.device' | tr '\n' ' ')"
adb shell 'command -v twrp >/dev/null' || { echo "recovery has no 'twrp' command (not TWRP/OrangeFox?)" >&2; exit 1; }

say "pushing $(basename "$ZIP") to /tmp"
adb push "$ZIP" /tmp/ >/dev/null
adb shell "sha256sum /tmp/$(basename "$ZIP")" | cut -c1-64 | grep -qx "$(sha256sum "$ZIP" | cut -c1-64)" || { echo "sha256 mismatch after push" >&2; exit 1; }

say "twrp install"
adb shell "twrp install /tmp/$(basename "$ZIP")" 2>&1 | tail -15
adb shell 'grep -aE "Theettam|Done|Error|Updater process ended" /tmp/recovery.log 2>/dev/null | tail -5' || true

say "rebooting to system"
adb reboot
sleep 15
wait_for device 300
say "waiting for boot_completed"
for _ in $(seq 1 36); do
  [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ] && break
  sleep 5
done
say "booted: $(adb shell 'uname -r; uptime' | tr '\n' ' ')"
if [ -n "$REL" ]; then
  adb push scripts/device/postflash-check.sh /data/local/tmp/ >/dev/null 2>&1 || true
  say "postflash-check"
  adb shell "sh /data/local/tmp/postflash-check.sh $REL $FLAVOR" | grep -E '^(FAIL|PASS=|VERDICT)' || true
fi
