#!/system/bin/sh
# Theettam Trip Mode — arm the wakelock blocker while the screen is off.
#
# The kernel does the work: CONFIG_BOEFFLA_WL_BLOCKER refuses named wakeup sources
# in wakeup_source_activate(), so a driver holding one cannot keep the AP awake.
# That is the part userspace cannot do -- it can see every wakeup source and
# refuse none of them.
#
# All this does is decide WHEN. Blocking the data path permanently means messages
# arrive late all day; blocking it only while the screen is off means the phone
# sleeps at night and behaves normally when you are using it.

MODDIR=${0%/*}
CONF="$MODDIR/trip.conf"
WLB=/sys/devices/virtual/misc/boeffla_wakelock_blocker/wakelock_blocker
LOG=/data/adb/theettam_trip.log

log() { echo "$(date '+%m-%d %H:%M:%S') $*" >> "$LOG"; }

# Only ever keep the last ~200 lines; a logfile is not a feature.
trim() { [ -f "$LOG" ] && [ "$(wc -l < "$LOG")" -gt 400 ] && tail -200 "$LOG" > "$LOG.t" && mv "$LOG.t" "$LOG"; }

conf() { sed -n "s/^$1=//p" "$CONF" 2>/dev/null | head -1; }

# Wait for boot; sysfs and dumpsys are not there yet at service.sh time.
until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 5; done
sleep 20

if [ ! -w "$WLB" ]; then
	log "no boeffla wakelock blocker at $WLB -- this kernel does not have it. Exiting."
	exit 0
fi

[ "$(conf enabled)" = "1" ] || { log "disabled in trip.conf. Exiting."; exit 0; }

LIST="$(conf list)"
POLL="$(conf poll)"; [ -n "$POLL" ] || POLL=15
CHG="$(conf unblock_on_charger)"

log "started. kernel blocker present, poll=${POLL}s"
log "list: $LIST"

screen_is_on() {
	# mWakefulness is the most reliable across ROMs; fall back to display state.
	local w
	w="$(dumpsys power 2>/dev/null | grep -m1 'mWakefulness=' | cut -d= -f2)"
	case "$w" in
		Awake) return 0 ;;
		Asleep|Dozing) return 1 ;;
	esac
	dumpsys display 2>/dev/null | grep -qm1 'mScreenState=ON' && return 0
	return 1
}

charging() {
	[ "$CHG" = "1" ] || return 1
	local s
	s="$(cat /sys/class/power_supply/battery/status 2>/dev/null)"
	[ "$s" = "Charging" ] || [ "$s" = "Full" ]
}

armed=-1
arm()   { echo "$LIST" > "$WLB" 2>/dev/null && { armed=1; log "armed (screen off)"; }; }
disarm() { echo "" > "$WLB" 2>/dev/null && { armed=0; log "cleared"; }; }

disarm   # never inherit state from a previous boot

while true; do
	if screen_is_on || charging; then
		[ "$armed" != "0" ] && disarm
	else
		[ "$armed" != "1" ] && arm
	fi
	trim
	sleep "$POLL"
done
