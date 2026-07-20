#!/bin/bash
# Hard gate: Module.symvers CRC diff against baseline for core-struct-exporting objects.
# Usage: kabi_symvers_gate.sh <baseline_Module.symvers> <new_Module.symvers>
# Exit 0 if safe; exit 1 if any core-related CRC shifted.
set -euo pipefail
BASE="${1:?baseline Module.symvers}"
NEW="${2:?new Module.symvers}"
OUT="${3:-/tmp/kabi_symvers_diff.txt}"

if [[ ! -f "$BASE" || ! -f "$NEW" ]]; then
  echo "::error::symvers missing base=$BASE new=$NEW"
  exit 2
fi

# Normalize: symbol type crc (drop path noise if present)
norm() {
  # Module.symvers format: 0xCRC\tname\tmodule\texport
  awk '{print $1"\t"$2}' "$1" | sort -k2,2
}

norm "$BASE" > /tmp/sym_base.norm
norm "$NEW"  > /tmp/sym_new.norm

# Full diff first
diff -u /tmp/sym_base.norm /tmp/sym_new.norm > "$OUT" || true

# Core symbol name patterns that boot-kill if CRC shifts (BOOT-NOTES + prompt)
# Match symbols that are known to encode core struct layouts via genksyms.
CORE_PAT='__put_task_struct|wake_up_process|sched_setscheduler|set_cpus_allowed_ptr|runqueues|vfs_getattr|inode_init_always|module_layout|pm_relax|wakeup_source_activate|__alloc_skb|register_netdev|css_set|nr_cpu_ids'

if [[ ! -s "$OUT" ]]; then
  echo "[kabi] EMPTY diff — Module.symvers identical (normalized). PASS"
  exit 0
fi

# Filter to core symbols only
CORE_HITS=$(grep -E "^[+-]0x" "$OUT" | grep -E "$CORE_PAT" || true)
if [[ -z "$CORE_HITS" ]]; then
  echo "[kabi] Diff non-empty but NO core-struct CRC hits matched. Review full diff:"
  head -40 "$OUT"
  echo "[kabi] Treating as WARN-only (non-core). PASS with warning."
  exit 0
fi

echo "::error::KABI CRC shift on core symbols — FAIL"
echo "$CORE_HITS" | head -80
echo "--- full core-related context ---"
grep -E "$CORE_PAT" "$OUT" | head -120 || true
exit 1
