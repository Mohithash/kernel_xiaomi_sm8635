#!/system/bin/sh
MODDIR=${0%/*}
# Run early so values are in place before any app reads them.
sh "$MODDIR/hideprops.sh" "$MODDIR"
