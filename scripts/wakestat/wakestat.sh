#!/system/bin/sh
# wakestat — find out what actually keeps peridot awake.
#
# Reads what the kernel already knows and nobody reads:
#
#   /sys/kernel/debug/wakeup_sources          per-source prevent_suspend_time
#   /sys/kernel/wakeup_reasons/last_resume_reason   which IRQ resumed the AP
#   /sys/kernel/wakeup_reasons/last_suspend_time    how long we actually slept
#
# Rank by total_time (col 7): how long each source was held. Not by
# prevent_suspend_time (col 10) -- the obvious choice, and dead on this kernel:
# it is only accumulated when ws->autosleep_enabled, that flag is only ever set by
# kernel/power/autosleep.c, and CONFIG_PM_AUTOSLEEP is not set here. Android does
# not use autosleep; it suspends from userspace via the SystemSuspend HAL and
# /sys/power/wakeup_count. So column 10 reads 0 for every source on every sample,
# and a tool ranking by it reports "nothing is wrong" no matter what is wrong.
#
# What matters is not how often a source fired but how long it was held: 10,000
# events holding 0ms cost nothing; 3 events holding 40 minutes is the bill.
#
# Usage, on-device as root:
#     wakestat.sh start          # before bed, screen off
#     wakestat.sh report         # in the morning
#
# It only reads. Nothing is blocked, frozen, or changed.
set -u

STATE=/data/local/tmp/wakestat
WS=/sys/kernel/debug/wakeup_sources
WR=/sys/kernel/wakeup_reasons

die() { echo "[!] $*"; exit 1; }

need_root() { [ "$(id -u)" = "0" ] || die "run as root (su)"; }

mount_debugfs() {
	[ -r "$WS" ] && return 0
	mount -t debugfs debugfs /sys/kernel/debug 2>/dev/null
	[ -r "$WS" ] || die "cannot read $WS (debugfs not mounted?)"
}

snap() {
	mkdir -p "$STATE"
	cat "$WS" > "$STATE/ws.$1" 2>/dev/null || die "read $WS failed"
	date +%s > "$STATE/t.$1"
	{
		echo "resume_reason: $(cat $WR/last_resume_reason 2>/dev/null || echo n/a)"
		echo "suspend_time : $(cat $WR/last_suspend_time 2>/dev/null || echo n/a)"
	} > "$STATE/wr.$1"
}

case "${1:-}" in
start)
	need_root; mount_debugfs
	rm -rf "$STATE"; snap a
	echo "[+] baseline taken $(date '+%H:%M:%S')"
	echo "    sources tracked: $(( $(wc -l < "$STATE/ws.a") - 1 ))"
	echo "    battery now    : $(cat /sys/class/power_supply/battery/capacity 2>/dev/null || echo '?')%"
	echo ""
	echo "    Screen off and leave it. Run 'wakestat.sh report' when you wake up."
	;;

report)
	need_root; mount_debugfs
	[ -f "$STATE/ws.a" ] || die "no baseline — run 'wakestat.sh start' first"
	snap b
	ta=$(cat "$STATE/t.a"); tb=$(cat "$STATE/t.b"); el=$((tb - ta))
	[ "$el" -gt 0 ] || die "no time elapsed"

	echo "=== wakestat: $((el / 60)) min elapsed ==="
	echo "  last resume reason : $(cat $WR/last_resume_reason 2>/dev/null | head -1)"
	echo "  last suspend time  : $(cat $WR/last_suspend_time 2>/dev/null | head -1)"
	echo "  battery now        : $(cat /sys/class/power_supply/battery/capacity 2>/dev/null || echo '?')%"
	echo ""
	echo "=== who prevented sleep, ranked by time (ms) ==="
	echo ""

	# wakeup_sources columns:
	# name active_count event_count wakeup_count expire_count active_since
	# total_time max_time last_change prevent_suspend_time
	awk -v elapsed="$el" '
	FNR==NR {
		if (FNR>1) { pa[$1]=$7+0; ca[$1]=$2+0 }
		next
	}
	FNR>1 {
		dp = ($7+0)  - (($1 in pa) ? pa[$1] : 0)     # delta total_time (col 7; see header)
		dc = ($2+0)  - (($1 in ca) ? ca[$1] : 0)     # delta active_count
		if (dp > 0 || dc > 0) { rows[n++] = sprintf("%12d|%8d|%s", dp, dc, $1) }
		tot += dp
	}
	END {
		if (n == 0) { print "  no source was held at all. Either the phone never woke,"
		              print "  or debugfs is lying. Check last_suspend_time above."; exit }
		# rank by prevent time
		for (i=0;i<n;i++) for (j=i+1;j<n;j++) {
			split(rows[i],x,"|"); split(rows[j],y,"|")
			if ((y[1]+0) > (x[1]+0)) { t=rows[i]; rows[i]=rows[j]; rows[j]=t }
		}
		printf "  %-34s %12s %9s %8s\n", "SOURCE", "HELD(ms)", "TIMES", "% OF RUN"
		shown = (n > 15) ? 15 : n
		for (i=0;i<shown;i++) {
			split(rows[i],f,"|")
			printf "  %-34s %12d %9d %7.1f%%\n", f[3], f[1], f[2], (f[1]/10)/elapsed
		}
		printf "\n  total awake attributable to wakelocks: %d ms (%.1f%% of the run)\n",
		       tot, (tot/10)/elapsed
		print  "\n  Reading it:"
		print  "   - a source near the top with a big %  is your drain"
		print  "   - names like IPA_WS / qcom_rx_wakelock / *ipa* are the DATA path:"
		print  "     something is pushing packets at you (FCM, sync). A module that"
		print  "     freezes apps fixes those, because frozen apps hold no sockets."
		print  "   - names tied to the modem control path are calls/SMS. Leave them."
		print  "   - if the total is a few percent, there is nothing here worth"
		print  "     building. That is a real result too."
	}' "$STATE/ws.a" "$STATE/ws.b"
	;;

*)
	echo "usage: wakestat.sh start | report"
	echo ""
	echo "  start   snapshot before an idle period (screen off)"
	echo "  report  rank what kept the phone awake since"
	;;
esac
