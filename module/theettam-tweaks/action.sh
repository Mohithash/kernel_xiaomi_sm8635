#!/system/bin/sh
# Theettam Tweaks — Action button: cycle PROFILE battery -> balanced -> performance.
# Re-applies the static VM/IO tuning immediately; screen-off levers pick up the new
# profile on the next reboot (or reboot now for a fully clean switch).

MODDIR=${0%/*}
CONF="$MODDIR/tweaks.conf"
cur=$(sed -n 's/^PROFILE=//p' "$CONF" 2>/dev/null | head -1)
case "$cur" in
	battery)     new=balanced ;;
	balanced)    new=performance ;;
	performance) new=battery ;;
	*)           new=balanced ;;
esac
sed -i "s/^PROFILE=.*/PROFILE=$new/" "$CONF"
echo "Profile: ${cur:-?} -> $new"

# apply VM/IO now
sh "$MODDIR/post-fs-data.sh" && echo "VM/IO tuning re-applied."
echo "Screen-off levers (wakelock trip, CPU cap) switch on next reboot."
