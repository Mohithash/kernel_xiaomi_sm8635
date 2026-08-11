#!/system/bin/sh
WLB=/sys/devices/virtual/misc/boeffla_wakelock_blocker/wakelock_blocker

ui_print ""
ui_print "  Theettam Tweaks"
ui_print "  ---------------"
ui_print "  Modular battery / performance levers."
ui_print "  Everything is off-by-default-safe and reverts on uninstall + reboot."
ui_print ""

PROFILE="$(sed -n 's/^PROFILE=//p' "$MODPATH/tweaks.conf" 2>/dev/null | head -1)"
ui_print "  Profile: ${PROFILE:-balanced}  (battery | balanced | performance)"
ui_print "  + VM + I/O tuning applied on boot"

if [ -e "$WLB" ]; then
	ui_print "  + kernel wakelock blocker found -> screen-off trip active"
	ui_print "    (blocks modem DATA wakelocks while screen off;"
	ui_print "     calls, SMS, alarms and paging are NOT touched)"
else
	ui_print "  - no Boeffla wakelock blocker on this kernel:"
	ui_print "    the screen-off trip lever will stay off (VM/IO still apply)"
fi

ui_print ""
ui_print "  Config: /data/adb/modules/theettam_tweaks/tweaks.conf"
ui_print "  Switch profile: the module Action button, or edit PROFILE + reboot"
ui_print "  Log:    /data/adb/theettam_tweaks.log"
ui_print ""

set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/service.sh"      0 0 0755
set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
set_perm "$MODPATH/action.sh"       0 0 0755
