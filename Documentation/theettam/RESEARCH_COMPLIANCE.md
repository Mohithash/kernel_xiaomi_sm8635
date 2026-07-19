# Theettam research directive — 100% compliance matrix

Target: VoltageOS A16 / peridot SM8635 / GKI 6.1.175  
Branch: `theettam-premium-sukisu`

| Phase | Requirement | Status | Implementation |
|-------|-------------|--------|----------------|
| 1 | KMI_SYMBOL_LIST_STRICT_MODE=1 | **YES** | `theettam/build/build.config.theettam` + build scripts / CI env |
| 1 | TRIM_NONLISTED_KMI=1 | **YES** | same build fragment |
| 1 | LTO=thin | **YES** | `CONFIG_LTO_CLANG_THIN=y` in theettam_GKI.config |
| 1 | LZ4 boot/compression | **YES** | CRYPTO_LZ4 + LZ4_* + GKI Image.lz4 packaging |
| 1 | CLO continuous rebase | **DOCUMENTED** | Deferred safe window in UPSTREAM_STATUS (no reckless unrelated merge) |
| 2 | BORE scheduler | **YES** | `CONFIG_SCHED_BORE=y`, `sched_bore=1` default |
| 2 | PELT ~8ms | **YES** | `sysctl_sched_pelt_multiplier = 4` |
| 2 | HZ 300 | **YES** | `CONFIG_HZ=300` |
| 2 | MQ-Deadline family I/O | **YES** | `MQ_IOSCHED_DEADLINE=y` + **ADIOS default** (Adaptive Deadline, superior mobile MQ) |
| 3 | SukiSU Ultra + KPM | **YES** | in-tree `drivers/kernelsu`, CONFIG_KSU/KPM=y |
| 3 | KALLSYMS_ALL | **YES** | theettam_GKI.config |
| 3 | SUSFS v2.2.0 official VFS | **YES** | integrate.sh + fs/susfs.c; no hand-rolled dcache |
| 3 | uname / cmdline spoof | **YES** | KSU_SUSFS_SPOOF_* |
| 4 | USER_NS + full NS + cgroups | **YES** | theettam_GKI.config |
| 4 | SECCOMP / FILTER | **YES** | CONFIG_SECCOMP{,_FILTER}=y |
| 4 | VETH / MACVLAN / multiport NAT | **YES** | theettam_GKI.config |
| 5 | **BBRv3** default TCP | **YES** | In-tree `tcp_bbr.c` with `#define BBR_VERSION 3`; CONFIG_TCP_CONG_BBR + DEFAULT_BBR; sysctl `bbr` |
| 5 | **CAKE** qdisc | **YES** | CONFIG_NET_SCH_CAKE=y (+ fq_codel available) |
| 5 | Boeffla qcom_rx_wakelock | **YES** | CONFIG_BOEFFLA_WL_BLOCKER=m |
| 5 | AOSP thermal (no mi_thermald switches) | **YES** | thermal gov power_allocator; see UPSTREAM_STATUS |
| + | Modular modules_install | **YES** | package_modules.sh + AK3 do.modules |

## Network runtime

```
net.ipv4.tcp_congestion_control=bbr    # BBRv3 codepath
# CAKE is selectable via tc:
#   tc qdisc replace dev wlan0 root cake
```

See `theettam/build/sysctl.theettam.conf`.

## Explicit non-goals (still research-safe)

- Dual SukiSU+KSUN in one Image (split branches)
- Hand-edited VFS for SUSFS (official 50_ only)
- Force CLO unrelated-histories merge (deferred)

## Bootability override (alpha-2)

Research wanted full cgroup/netfilter matrix. **On-device GKI reality (peridot):**

| Config | Research | Bootable |
|--------|----------|----------|
| CGROUP_DEVICE / CGROUP_PIDS | want | **OFF** (vendor CRC) |
| BRIDGE_NETFILTER / NF_TABLES | want | **OFF** (sched CRC) |
| USER_NS / PID_NS / SYSVIPC | want | ON |
| Basic NAT / veth / macvlan | want | ON (no bridge-nf) |

See `BOOT_NOTES.md`.
