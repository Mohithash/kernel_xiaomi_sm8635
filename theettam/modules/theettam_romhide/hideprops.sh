#!/system/bin/sh
# Theettam ROM Prop Hide — strip VoltageOS / Custom-ROM identity properties,
# and delete sys.oem_unlock_allowed (its presence contradicts the locked state).
MODDIR="${1:-${0%/*}}"
LOG="$MODDIR/romhide.log"

RESETPROP=resetprop
[ -x /data/adb/ksu/bin/resetprop ] && RESETPROP=/data/adb/ksu/bin/resetprop
[ -x /data/adb/magisk/resetprop ] && RESETPROP=/data/adb/magisk/resetprop

echo "$(date '+%F %T') romhide run via $RESETPROP" >> "$LOG"

for p in \
  ro.modversion \
  ro.voltage.version \
  ro.voltage.build.date \
  ro.voltage.build.status \
  ro.voltage.buildtype \
  ro.voltage.device \
  ro.voltage.fingerprint \
  ro.voltage.maintainer.gpg_key \
  ro.voltage.maintainer.gpg_uid \
  ro.voltage.platform_release_or_codename \
  org.voltage.version \
  sys.oem_unlock_allowed ; do
  $RESETPROP --delete "$p" 2>/dev/null && echo "  deleted $p" >> "$LOG"
done

$RESETPROP ro.build.flavor peridot_global-user 2>/dev/null && echo "  ro.build.flavor=peridot_global-user" >> "$LOG"
echo "  done" >> "$LOG"
