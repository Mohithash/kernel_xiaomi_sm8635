#!/system/bin/sh
# Theettam Tweaks — screen-state levers.
#
# Two things happen only while the screen is OFF, and both undo themselves the
# moment the screen turns on or the phone is charging:
#   1. wakelock trip  — the kernel Boeffla blocker refuses the data-path wakeup
#                       sources named in trip_list (calls/alarms/paging untouched).
#   2. CPU cap (battery profile only) — the prime cluster's scaling_max_freq is
#                       capped; the governor still scales below it. Restored on wake.
# Nothing here is permanent: state is reset at boot and on uninstall+reboot.

MODDIR=${0%/*}
CONF="$MODDIR/tweaks.conf"
WLB=/sys/devices/virtual/misc/boeffla_wakelock_blocker/wakelock_blocker
LOG=/data/adb/theettam_tweaks.log
SAVE=/data/adb/theettam_tweaks.pmax

log()  { echo "$(date '+%m-%d %H:%M:%S') $*" >> "$LOG"; }
trim() { [ -f "$LOG" ] && [ "$(wc -l < "$LOG")" -gt 400 ] && tail -200 "$LOG" > "$LOG.t" && mv "$LOG.t" "$LOG"; }
conf() { sed -n "s/^$1=//p" "$CONF" 2>/dev/null | head -1; }

# sysfs/dumpsys aren't ready at service.sh time
until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 5; done
sleep 20

PROFILE="$(conf PROFILE)"; [ -n "$PROFILE" ] || PROFILE=balanced
TRIP="$(conf trip)"
LIST="$(conf trip_list)"
POLL="$(conf trip_poll)"; [ -n "$POLL" ] || POLL=15
CHG="$(conf trip_unblock_on_charger)"
CAP=0; [ "$PROFILE" = "battery" ] && CAP=1

# trip needs the kernel blocker; disable the lever if absent
[ "$TRIP" = "1" ] && [ -w "$WLB" ] || TRIP=0

# find the prime cpufreq policy (highest max freq) for the cap
PRIME=""; PMAX=0
for p in /sys/devices/system/cpu/cpufreq/policy*; do
	m=$(cat "$p/cpuinfo_max_freq" 2>/dev/null || echo 0)
	[ "$m" -gt "$PMAX" ] && { PMAX=$m; PRIME=$p; }
done
CAPFREQ=$(( PMAX * 65 / 100 ))   # governor rounds to nearest available freq
[ -n "$PRIME" ] && [ -w "$PRIME/scaling_max_freq" ] || CAP=0

screen_is_on() {
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
	local s; s="$(cat /sys/class/power_supply/battery/status 2>/dev/null)"
	[ "$s" = "Charging" ] || [ "$s" = "Full" ]
}

trip_on()  { echo "$LIST" > "$WLB" 2>/dev/null; }
trip_off() { echo ""      > "$WLB" 2>/dev/null; }
cap_on()   { cat "$PRIME/scaling_max_freq" > "$SAVE" 2>/dev/null; echo "$CAPFREQ" > "$PRIME/scaling_max_freq" 2>/dev/null; }
cap_off()  { echo "$PMAX" > "$PRIME/scaling_max_freq" 2>/dev/null; }   # always restore to true max

# clean slate at boot: never inherit a capped/armed state from a crash
[ "$TRIP" = "1" ] && trip_off
[ "$CAP"  = "1" ] && { cap_off; rm -f "$SAVE"; }

[ "$TRIP" = "1" ] || [ "$CAP" = "1" ] || { log "no screen-off levers active (profile=$PROFILE); exiting"; exit 0; }
log "started profile=$PROFILE trip=$TRIP cap=$CAP prime=$PRIME capfreq=$CAPFREQ poll=${POLL}s"

state=-1
while true; do
	if screen_is_on || charging; then
		if [ "$state" != "0" ]; then
			[ "$TRIP" = "1" ] && trip_off
			[ "$CAP"  = "1" ] && cap_off
			state=0; log "screen on / charging -> levers off"
		fi
	else
		if [ "$state" != "1" ]; then
			[ "$TRIP" = "1" ] && trip_on
			[ "$CAP"  = "1" ] && cap_on
			state=1; log "screen off -> levers on"
		fi
	fi
	trim
	sleep "$POLL"
done
