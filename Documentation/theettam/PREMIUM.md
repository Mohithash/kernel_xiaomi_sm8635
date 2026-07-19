# Theettam Premium

**SukiSU-Ultra + SUSFS v2.2.0 + Droidspaces** on **ACK 6.1.175** (BORE + ADIOS)

| Layer | Implementation |
|-------|----------------|
| Base | `theettam-source-fix` product freeze (6.1.175) |
| Root | SukiSU-Ultra `susfs_new` @ `278d822a4ebd214bcfd774b7910cb11cdc560bb9` + KPM |
| Hiding | SUSFS v2.2.0 via `scripts/susfs/integrate.sh` (official VFS) |
| Containers | USER_NS + full NS + veth/macvlan/NAT (`theettam_GKI.config`) |
| Sched | BORE on, PELT multiplier 4 (~8ms) |
| Power | Boeffla blocks qcom_rx_wakelock |
| KMI | `KMI_SYMBOL_LIST_STRICT_MODE=1` at build |

## Manager

Use the **SukiSU** manager app (not KernelSU-Next).

## Build

```bash
export KMI_SYMBOL_LIST_STRICT_MODE=1
export PATH=$HOME/clang/bin:$PATH
make O=out LLVM=1 LLVM_IAS=1 \
  gki_defconfig vendor/pineapple_GKI.config vendor/peridot_GKI.config vendor/theettam_GKI.config
make O=out LLVM=1 LLVM_IAS=1 -j$(nproc)
```

## Modules

See [`MODULES.md`](MODULES.md). Image-only kernels are incomplete on GKI —
this branch packages `modules_install` + AnyKernel modular extras.
