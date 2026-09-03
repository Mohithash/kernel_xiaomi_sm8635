#!/bin/bash
# symvers-diff.sh — KABI pre-flash check (docs/BOOT-NOTES.md Rule 2).
#
# Usage: scripts/ci/symvers-diff.sh <baseline Module.symvers> <candidate Module.symvers> [accepted-drift.txt]
#
# Prints one line per differing export: CHANGED / REMOVED / ADDED / ACCEPTED.
# Summary on stderr. Exit 1 if any CRC CHANGED or symbol REMOVED; ADDED never
# fails (a new export cannot break a prebuilt module), and neither does
# ACCEPTED: a CHANGED symbol whose *new* CRC is listed in the optional
# accepted-drift file, i.e. a shift that a real device has already booted
# through with the stock vendor_dlkm (see scripts/ci/kmi-baseline/README.md).
#
# Accepted-drift file format, one per line, '#' comments allowed:
#   <symbol> <new-crc>   # why this is known-safe (boot evidence)
set -euo pipefail
A="$1"; B="$2"; ACC="${3:-}"

# join(1) compares keys bytewise and needs its inputs sorted the same way; in a
# UTF-8 locale sort(1) collates differently (and sorts the whole line, not the
# key), which made join warn "input is not in sorted order" and mis-pair rows.
export LC_ALL=C
norm(){ awk '{print $2"\t"$1}' "$1" | sort -t $'\t' -k1,1; }   # symbol<TAB>crc
acc(){
  echo $'__accepted_drift_header__\t-'          # sentinel: keeps NR==FNR valid when the list is empty
  if [ -n "$ACC" ] && [ -f "$ACC" ]; then
    sed 's/#.*//' "$ACC" | awk 'NF>=2 {print $1"\t"$2}'
  fi
}

join -t $'\t' -a1 -a2 -e MISSING -o 0,1.2,2.2 <(norm "$A") <(norm "$B") \
 | awk -F'\t' '
   NR==FNR { acc[$1"\t"$2]=1; next }
   $2!=$3 {
     if      ($2=="MISSING")        { add++; tag="ADDED  " }
     else if ($3=="MISSING")        { del++; tag="REMOVED" }
     else if (($1"\t"$3) in acc)    { okd++; tag="ACCEPTED" }
     else                           { chg++; tag="CHANGED" }
     print tag"\t"$1"\t"$2"\t"$3
   }
   END {
     printf("SUMMARY changed=%d removed=%d added=%d accepted=%d\n", chg, del, add, okd) > "/dev/stderr"
     if (chg+del>0) exit 1
   }' <(acc) -
