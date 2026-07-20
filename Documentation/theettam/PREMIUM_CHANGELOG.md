# Theettam Premium (SukiSU + KPM + SUSFS + DroidSpaces) — change log + KABI

**Base:** `peridot-6.1.175` @ boot-confirmed HEAD (never 173 / 209fbd25)  
**Contract:** `docs/BOOT-NOTES.md`  
**Gate:** `theettam/scripts/kabi_symvers_gate.sh` (Module.symvers CRC)

## Category A

| Change | Implementation | Expected CRC | Notes |
|--------|----------------|--------------|-------|
| PELT half-life 8ms | `kernel/sched/sched-pelt.h` LOAD_AVG_PERIOD 8 / LOAD_AVG_MAX 17249 | empty core | constants only |
| mq-deadline front merges off | already `dd->front_merges = 0` in base | n/a | verified present |
| ZRAM multi-comp | `theettam_premium.config` CONFIG_ZRAM_MULTI_COMP | empty core | if Kconfig exists |
| Boeffla-style WL | deferred to CI follow-up if wakeup.c path differs | must not touch wakeup_source layout | name filter only |

## Category B

| Change | Implementation | Gate |
|--------|----------------|------|
| SukiSU-Ultra + KPM + SUSFS 2.2.0 | `scripts/susfs/integrate-sukisu.sh`, pin susfs_new@278d822a, susfs@8199bb65 | required |
| DroidSpaces | `scripts/droidspaces/integrate.sh` + droidspaces.config (no CGROUP_DEVICE/PIDS, no NF_TABLES/BRIDGE_NF) | required; task_struct reserve slots 6/7/8 |

## Category C — FORBIDDEN (forced off in build script)

- CONFIG_CGROUP_PIDS, CONFIG_CGROUP_DEVICE
- CONFIG_NF_TABLES, CONFIG_BRIDGE_NETFILTER
- SukiSU v4.1.3 blind swap
- HZ change (base is HZ_300 and boots — do not retune)

## BORE

Already `CONFIG_SCHED_BORE=y` on base gki_defconfig (v2.1 lineage). No extra BORE field patching in this pass; shipping base BORE only.

## MGLRU

Already `CONFIG_LRU_GEN=y` on base. No change; boot-confirmed base already carries it.

## CI

Workflow `.github/workflows/build-theettam-premium.yml` runs baseline + premium builds and **fails** if the KABI gate fails.
