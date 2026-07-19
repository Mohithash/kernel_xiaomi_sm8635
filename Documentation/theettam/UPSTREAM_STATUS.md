# Theettam upstream status (maintainer decision)

Updated: 2026-07-19T18:57:49Z  
Branch: `theettam-source-fix` / `theettam-voltage-opt`  
HEAD: 0185411505

## Kernel base

| Item | Pin | Rationale |
|------|-----|-----------|
| Linux / ACK | **6.1.175** (android14-6.1 LTS level) | Already integrated with BORE+ADIOS (KABI-safe) |
| Full `android14-6.1-lts` tip merge | **Deferred** | No shared merge-base with shallow/remote ACK object set; forcing `--allow-unrelated-histories` is reckless |
| GuidixX 16.2 | **Not merged** | Older product tree; would regress LTS/KMI work |
| Future ACK | Rebase window when merge-base available | Cherry-pick ANDROID: GKI commits only |

## Root stack (Phase 1)

| Component | Pin | Notes |
|-----------|-----|--------|
| KernelSU-Next | **v3.3.0** (latest stable as of audit) | Official |
| SUSFS driver pair | **pershoot/KernelSU-Next@9c46185e** | Matched SUSFS pre-integration |
| SUSFS fs | **v2.2.0** `50_add_susfs_in_gki-android14-6.1.patch` | Official VFS only — no hand-edit dcache/readdir/stat/open |
| KPM | CONFIG_KPM=y + KALLSYMS_ALL | In theettam_GKI.config |
| Integrate | `bash theettam/scripts/integrate_root.sh ksun_susfs` | Run before release build |

## Product (Phase 2–3) — in tree

| Feature | Status |
|---------|--------|
| vendor/theettam_GKI.config | containers USER_NS, netfilter, root flags |
| BORE | sched_bore=1 default |
| ADIOS | MQ default when enabled |
| PELT | multiplier **4** (~8ms half-life) |
| Boeffla WL | qcom_rx_wakelock default block + wakeup hook |
| Thermal | AOSP thermal framework; no mi_thermald kernel switches |

## Build (when ready — not this commit)

```bash
export KMI_SYMBOL_LIST_STRICT_MODE=1
export PATH=/root/claude/clang/bin:$PATH
bash theettam/scripts/integrate_root.sh ksun_susfs
bash theettam/scripts/build_theettam.sh
```

## Premium branch (`theettam-premium-sukisu`)

- SukiSU-Ultra: `278d822a4ebd214bcfd774b7910cb11cdc560bb9`
- SUSFS: official integrate via `scripts/susfs/integrate.sh`
- Droidspaces: enabled in `theettam_GKI.config`
- `drivers/kernelsu` committed in-tree

## RESEARCH 100% (premium)

- BBRv3: **in-tree** (`#define BBR_VERSION 3` in `net/ipv4/tcp_bbr.c`) — patch series already applied
- CAKE: enabled in `theettam_GKI.config`
- Build env: `theettam/build/build.config.theettam` (KMI strict + TRIM)
- Matrix: `Documentation/theettam/RESEARCH_COMPLIANCE.md`
