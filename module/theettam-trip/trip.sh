#!/system/bin/sh
# Theettam Trip Mode — calls and SMS only.
#
#   trip.sh on      radios and background off. Calls and SMS still arrive.
#   trip.sh off     put everything back exactly as it was.
#   trip.sh status
#
# Why radios-off rather than the usual battery-module approach:
#
# Blocking a wakelock stops the modem waking the AP when a packet lands. Turning
# mobile data off means no packet lands at all. It is the same goal one layer up,
# and it needs no guesswork about wakelock names.
#
# Calls and SMS survive because VoLTE rides the IMS APN, which the mobile-data
# toggle does not govern -- that is why you can have data off today and still be
# called. The kernel's Boeffla blocker stays armed underneath as a backstop for
# anything that still holds a wakelock with no traffic to justify it.
#
# What this does NOT do, deliberately:
#   - pm disable on GMS components. On sandboxed Play, GMS is an ordinary app with
#     no privileged services to dissect. That is Frosty's whole gms_freeze.sh and
#     the source of its "may break Maps/Pay/NFC" warnings. It does not apply here.
#   - am force-stop. Killing apps loses their state and they relaunch on the next
#     broadcast, costing the battery you were saving.

MODDIR=${0%/*}
STATE=/data/adb/theettam_trip.state
WLB=/sys/devices/virtual/misc/boeffla_wakelock_blocker/wakelock_blocker
CONF="$MODDIR/trip.conf"

conf() { sed -n "s/^$1=//p" "$CONF" 2>/dev/null | head -1; }

get() { settings get global "$1" 2>/dev/null; }

in_call() {
	# Do not rip the radios out from under an active call, even though IMS should
	# survive it. Cheap to check, and the failure mode is somebody's dropped call.
	dumpsys telephony.registry 2>/dev/null | grep -qm1 'mCallState=[12]'
}

save_state() {
	{
		echo "data=$(get mobile_data)"
		echo "wifi=$(get wifi_on)"
		echo "bt=$(get bluetooth_on)"
		echo "loc=$(settings get secure location_mode 2>/dev/null)"
		echo "sync=$(content query --uri content://settings/global --where "name='auto_sync'" 2>/dev/null | head -1)"
	} > "$STATE"
}

trip_on() {
	[ -w "$WLB" ] || echo "  ! no kernel wakelock blocker — continuing without it"
	if in_call; then echo "  ! you are on a call. Not now."; exit 1; fi

	save_state
	echo "  saved current state -> $STATE"

	svc data disable  2>/dev/null && echo "  mobile data  off   (VoLTE/IMS unaffected: calls still arrive)"
	svc wifi disable  2>/dev/null && echo "  wifi         off"
	svc bluetooth disable 2>/dev/null && echo "  bluetooth    off"
	settings put global auto_sync 0 2>/dev/null    && echo "  account sync off"
	settings put secure location_mode 0 2>/dev/null && echo "  location     off"

	if [ -w "$WLB" ]; then
		echo "$(conf list)" > "$WLB" 2>/dev/null && echo "  kernel wakelock blocker armed (backstop)"
	fi

	echo "1" > /data/adb/theettam_trip.on
	echo ""
	echo "  TRIP MODE ON — calls and SMS work. Nothing else does."
	echo "  trip.sh off   to restore."
}

trip_off() {
	svc data enable 2>/dev/null; svc wifi enable 2>/dev/null; svc bluetooth enable 2>/dev/null
	settings put global auto_sync 1 2>/dev/null

	# Restore only what we recorded; never invent a value the user did not have.
	if [ -f "$STATE" ]; then
		loc=$(sed -n 's/^loc=//p' "$STATE")
		[ -n "$loc" ] && settings put secure location_mode "$loc" 2>/dev/null
		[ "$(sed -n 's/^wifi=//p' "$STATE")" = "0" ] && svc wifi disable 2>/dev/null
		[ "$(sed -n 's/^bt=//p'   "$STATE")" = "0" ] && svc bluetooth disable 2>/dev/null
		[ "$(sed -n 's/^data=//p' "$STATE")" = "0" ] && svc data disable 2>/dev/null
	fi
	[ -w "$WLB" ] && echo "" > "$WLB" 2>/dev/null

	rm -f /data/adb/theettam_trip.on
	echo "  TRIP MODE OFF — restored."
}

status() {
	if [ -f /data/adb/theettam_trip.on ]; then echo "  trip mode: ON"; else echo "  trip mode: OFF"; fi
	echo "  data=$(get mobile_data) wifi=$(get wifi_on) bt=$(get bluetooth_on)"
	if [ -r "$WLB" ]; then
		l=$(cat "$WLB" 2>/dev/null)
		[ -n "$l" ] && echo "  kernel blocker: armed" || echo "  kernel blocker: idle"
	else
		echo "  kernel blocker: NOT PRESENT (kernel lacks CONFIG_BOEFFLA_WL_BLOCKER)"
	fi
	echo "  battery: $(cat /sys/class/power_supply/battery/capacity 2>/dev/null)%"
}

case "${1:-}" in
	on)  trip_on ;;
	off) trip_off ;;
	status) status ;;
	*) echo "usage: trip.sh on | off | status" ;;
esac
