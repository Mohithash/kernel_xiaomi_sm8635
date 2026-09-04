#!/system/bin/sh
# log-audit.sh — the check postflash-check.sh deliberately is not.
#
# postflash-check answers "did it boot correctly" by grepping dmesg for a fixed
# set of hard failures. That is a gate, and it is narrow on purpose. This walks
# the logs looking for things that are wrong but not fatal: policy denials,
# native crashes, services that keep restarting, and driver errors that never
# reach the level of a WARN. Read-only, needs root.
#
#   adb shell su -c 'sh /data/local/tmp/log-audit.sh' | tee audit.txt

[ "$(id -u)" = 0 ] || { echo "needs root"; exit 1; }
sec(){ echo; echo "=== $1 ==="; }

sec "SELinux: is it real"
echo "  getenforce           = $(getenforce)"
echo "  /sys/fs/selinux/enforce = $(cat /sys/fs/selinux/enforce 2>/dev/null)"
echo "  ro.build.type        = $(getprop ro.build.type)   ro.debuggable = $(getprop ro.debuggable)"
echo "  ro.boot.selinux      = $(getprop ro.boot.selinux)  (leaks if 'permissive' while getenforce says Enforcing)"
echo "  policy version       = $(cat /sys/fs/selinux/policyvers 2>/dev/null)"

sec "AVC denials since boot, by source domain (triage: who is being denied what)"
dmesg 2>/dev/null | grep 'avc:  denied' > /data/local/tmp/.avc
echo "  total: $(wc -l < /data/local/tmp/.avc)"
echo "  --- by scontext ---"
grep -oE 'scontext=u:r:[a-z_0-9]+' /data/local/tmp/.avc | sort | uniq -c | sort -rn | head -12 | sed 's/^/   /'
echo "  --- by {perm} tcontext ---"
grep -oE '\{ [a-z_ ]+ \} for .*tcontext=u:object_r:[a-z_0-9]+' /data/local/tmp/.avc \
  | sed -E 's/.*(\{ [a-z_ ]+ \}).*tcontext=u:object_r:([a-z_0-9]+)/\1 -> \2/' | sort | uniq -c | sort -rn | head -12 | sed 's/^/   /'
echo "  --- denials naming the root engine (would be hiding leaks) ---"
grep -icE 'ksu|susfs|magisk' /data/local/tmp/.avc | sed 's/^/   count: /'
rm -f /data/local/tmp/.avc

sec "native crashes: tombstones and dropbox"
# Name the crashing process and say whether it is from THIS boot: a tombstone
# from a previous boot is history, not a live problem, and the distinction is
# the whole point of looking.
BOOTED=$(( $(date +%s) - $(cut -d. -f1 /proc/uptime) ))
for t in /data/tombstones/tombstone_*; do
  case "$t" in *.pb) continue;; esac
  [ -f "$t" ] || continue
  WHEN=$(stat -c%Y "$t" 2>/dev/null)
  D=$(( ${WHEN:-0} - BOOTED ))
  # Show the offset, not just the side of the boundary: a crash 46 s before
  # boot happened during the previous shutdown and is a different story from
  # one fifteen hours ago, and "previous boot" flattens both to the same word.
  if [ "$D" -ge 0 ]; then AGE="THIS BOOT +${D}s"
  else AGE="$(( -D / 60 ))min before boot"; fi
  printf '   %-16s %-22s %s\n' "$(basename $t)" "$AGE" \
     "$(grep -m1 '^Cmdline:' "$t" 2>/dev/null | cut -c10-70)"
  grep -m1 '^signal ' "$t" 2>/dev/null | sed 's/^/       /'
done
echo "  dropbox crash/anr entries in the last day:"
ls -lt /data/system/dropbox/ 2>/dev/null | grep -E 'crash|anr|watchdog' | head -6 | sed 's/^/   /'
echo "  (none listed above = none recorded)"

sec "services restarting (a loop means something is broken but retrying)"
dmesg 2>/dev/null | grep -oE "init: Service '[a-zA-Z0-9_.-]+'" | sort | uniq -c | sort -rn | head -8 | sed 's/^/   /'
echo "  --- services that exited with a nonzero status ---"
dmesg 2>/dev/null | grep -E "init: Service.*exited with status [1-9]" | head -6 | sed 's/^/   /'

sec "kernel errors below the WARN threshold"
# toybox grep has no \b word boundary - it errors out with "trailing backslash"
# and the section silently produces nothing. Match the surrounding characters.
dmesg 2>/dev/null | grep -icE '(^|[^a-z])error([^a-z]|$)' | sed 's/^/  lines containing error: /'
dmesg 2>/dev/null | grep -iE '(^|[^a-z])error([^a-z]|$)' | grep -ivE 'no error|error_report|0 errors' \
  | sed -E 's/^\[[0-9. ]+\] //; s/\[[0-9a-fx]+\]//g; s/[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]+//' \
  | sort | uniq -c | sort -rn | head -12 | cut -c1-150 | sed 's/^/   /'

sec "logcat: crashes, ANRs and fatals since boot"
logcat -d -b crash 2>/dev/null | tail -20 | sed 's/^/   /'
echo "  --- E/F level, most frequent tags ---"
logcat -d 2>/dev/null | grep -E '^[0-9-]+ [0-9:.]+ +[0-9]+ +[0-9]+ [EF] ' \
  | awk '{print $6}' | sort | uniq -c | sort -rn | head -12 | sed 's/^/   /'

sec "modules that failed to load"
dmesg 2>/dev/null | grep -iE 'module.*(fail|error|denied)|Unknown symbol|disagrees about' | head -6 | sed 's/^/   /'
echo "  loaded: $(lsmod | grep -vc '^Module')"

sec "verdict inputs"
echo "  uptime          = $(cut -d' ' -f1 /proc/uptime)s"
echo "  kernel taint    = $(cat /proc/sys/kernel/tainted)  (0x1000=out-of-tree, 0x200=warn, 0x2000=unsigned)"
echo "  oom kills       = $(dmesg 2>/dev/null | grep -ic 'out of memory\|oom-kill')"
