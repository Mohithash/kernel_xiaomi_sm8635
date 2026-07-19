# Theettam Premium

**100% research directive** — SukiSU-Ultra + SUSFS v2.2.0 + Droidspaces + BBRv3 + CAKE  
Base: **ACK 6.1.175** (BORE + ADIOS + PELT 8ms)

See [`RESEARCH_COMPLIANCE.md`](RESEARCH_COMPLIANCE.md) for the full matrix.

| Layer | Implementation |
|-------|----------------|
| Root | SukiSU-Ultra + KPM (in-tree) |
| Hide | SUSFS v2.2.0 (official VFS integrate) |
| Containers | USER_NS + NS + veth/macvlan/NAT + seccomp |
| Sched | BORE on, PELT×4 (~8ms), HZ=300 |
| I/O | ADIOS default (deadline family) + MQ_DEADLINE |
| Net | **BBRv3** (`tcp_bbr` / BBR_VERSION3) + **CAKE** + fq_codel |
| Power | Boeffla module (qcom_rx_wakelock) |
| KMI | `KMI_SYMBOL_LIST_STRICT_MODE=1` + `TRIM_NONLISTED_KMI=1` |
| Modules | `package_modules.sh` + AnyKernel do.modules |

## Build

```bash
source theettam/build/build.config.theettam
export PATH=$HOME/clang/bin:$PATH
make O=out LLVM=1 LLVM_IAS=1 \
  gki_defconfig vendor/pineapple_GKI.config vendor/peridot_GKI.config vendor/theettam_GKI.config
make O=out LLVM=1 LLVM_IAS=1 -j$(nproc)
OUT=out bash theettam/scripts/package_modules.sh
```
