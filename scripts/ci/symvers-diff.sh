#!/bin/bash
# symvers-diff.sh — KABI pre-flash check (docs/BOOT-NOTES.md Rule 2).
# Usage: scripts/ci/symvers-diff.sh <baseline Module.symvers> <candidate Module.symvers>
# Prints CHANGED/REMOVED/ADDED exported symbols; summary on stderr. Exit 1 if any CRC changed or symbol removed.
set -euo pipefail
A="$1"; B="$2"
norm(){ awk '{print $2"\t"$1}' "$1" | sort; }   # symbol<TAB>crc
join -t $'\t' -a1 -a2 -e MISSING -o 0,1.2,2.2 <(norm "$A") <(norm "$B") \
 | awk -F'\t' '$2!=$3 { if ($2=="MISSING") add++; else if ($3=="MISSING") del++; else chg++; print ($2=="MISSING"?"ADDED  ":($3=="MISSING"?"REMOVED":"CHANGED"))"\t"$1"\t"$2"\t"$3 }
   END { printf("SUMMARY changed=%d removed=%d added=%d\n", chg, del, add) > "/dev/stderr"; if (chg+del>0) exit 1 }'
