#!/system/bin/sh
WLB=/sys/devices/virtual/misc/boeffla_wakelock_blocker/wakelock_blocker

ui_print ""
ui_print "  Theettam Trip Mode"
ui_print "  ------------------"

if [ ! -e "$WLB" ]; then
	ui_print "  ! Your kernel has no Boeffla wakelock blocker."
	ui_print "  ! This module does nothing without it."
	ui_print "  ! Flash Theettam Kernel, or one with"
	ui_print "  ! CONFIG_BOEFFLA_WL_BLOCKER=y."
	abort   "  ! Aborting rather than installing a no-op."
fi

ui_print "  + kernel blocker found"
ui_print "  + blocks modem data wakelocks while screen is off"
ui_print "  + calls, SMS and alarms are NOT touched"
ui_print "  + clears itself on charger and screen-on"
ui_print ""
ui_print "  Config: /data/adb/modules/theettam_trip/trip.conf"
ui_print "  Log:    /data/adb/theettam_trip.log"
ui_print ""
set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/service.sh" 0 0 0755
