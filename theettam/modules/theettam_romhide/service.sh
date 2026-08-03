#!/system/bin/sh
MODDIR=${0%/*}
until [ "$(getprop sys.boot_completed)" = 1 ]; do sleep 2; done
sleep 6
sh "$MODDIR/hideprops.sh" "$MODDIR"
