# Theettam Premium (alpha)

peridot · 6.1.175 · Image-only AnyKernel · stock `vendor_dlkm`

**Zip:** [KSU-FIXED AnyKernel](https://github.com/Mohithash/kernel_xiaomi_sm8635/releases/download/theettam-premium-alpha-175-ksu/Theettam-Premium-SukiSU-KSU-FIXED-peridot-6.1.175-android14-11-ga3b9c44908dd-ab13320413-a20a40a59f46-20260720-0241.zip)  
**Tree:** [`a20a40a`](https://github.com/Mohithash/kernel_xiaomi_sm8635/commit/a20a40a59f46) on `theettam-premium-sukisu`  
**Uname:** `6.1.175-android14-11-ga3b9c44908dd-ab13320413`

Do not flash the older [`…-kabi`](https://github.com/Mohithash/kernel_xiaomi_sm8635/releases/tag/theettam-premium-alpha-175-kabi) zip — it boots with **no root** (`CONFIG_KSU` was never set). This build wires `drivers/kernelsu` and requires `CONFIG_KSU=y`.

---

## What it is

Single-flavor Image on the same **2.1 / `peridot-6.1.175`** base:

- [SukiSU Ultra](https://github.com/SukiSU-Ultra/SukiSU-Ultra) + KPM (pin `278d822a`)
- [SUSFS](https://gitlab.com/simonpunk/susfs4ksu) v2.2.0 (pin `8199bb65`)
- [DroidSpaces](https://github.com/ravindu644/Droidspaces-OSS) **safe** config only
- Small Category A tweaks (below)
- Build fails if core `Module.symvers` CRCs drift vs baseline

Not a daily-driver product release. For that use **[Theettam 2.1](https://github.com/Mohithash/kernel_xiaomi_sm8635/releases/tag/v2.1)**.

---

## Why “Premium” (vs 2.1)

| | 2.1 | Premium |
|--|--|--|
| Status | stable | alpha |
| Zips | 4 root flavors | 1 (SukiSU only) |
| Base | 6.1.175 + July CLO | same line (+premium commits) |
| DroidSpaces | not in main 2.1 assets | yes, safe set |
| Extra tunings | base only (BORE/ADIOS/BBRv3/…) | + PELT 8ms, ZRAM multi-comp, `qcom_rx_wakelock` name filter |
| KABI check | boot-tested release | Module.symvers gate in build |
| Manager | match the flavor you flash | SukiSU Ultra only |

Closest 2.1 zip: [SukiSU Ultra + SUSFS + KPM](https://github.com/Mohithash/kernel_xiaomi_sm8635/releases/download/v2.1/Theettam-2.1-SukiSU-Ultra-SUSFS2.2.0-KPM-peridot-6.1.175-android14-11-ga3b9c44908dd-ab13320413.zip). Premium is that idea plus DroidSpaces + Category A + the gate.

---

## What’s in / what’s out

**In**

- `CONFIG_KSU=y`, `CONFIG_KPM=y`, SUSFS options as integrated
- DroidSpaces with `SYSVIPC` via KABI reserve relocation (`scripts/droidspaces/integrate.sh`)
- PELT half-life 8ms; ZRAM multi-comp/LZ4/writeback fragment; name-only wakelock filter for `qcom_rx_wakelock`
- Base BORE / ADIOS / BBRv3 / MGLRU unchanged from 2.1 line

**Out (forced off — these bootlooped here)**

- `CONFIG_CGROUP_DEVICE`, `CONFIG_CGROUP_PIDS`
- `CONFIG_NF_TABLES`, `CONFIG_BRIDGE_NETFILTER`
- Full “wishlist” DroidSpaces net/cgroup set — **not** claimed. Safe subset only.

Evidence: [BOOT-NOTES](https://github.com/Mohithash/kernel_xiaomi_sm8635/blob/theettam-premium-sukisu/docs/BOOT-NOTES.md), [droidspaces-v1](https://github.com/Mohithash/kernel_xiaomi_sm8635/releases/tag/droidspaces-v1), [PREMIUM_CHANGELOG](https://github.com/Mohithash/kernel_xiaomi_sm8635/blob/theettam-premium-sukisu/Documentation/theettam/PREMIUM_CHANGELOG.md).

---

## Install

1. Backup boot (and vendor_boot if you can). Recovery + fastboot ready.
2. Flash the KSU-FIXED zip (sideload or file).
3. Install **only** SukiSU Ultra. Remove other KernelSU-family managers, then reboot (crowning is at boot).
4. Optional: `adb shell uname -a` / `adb shell su -c id`

---

## Refs

- [v2.1](https://github.com/Mohithash/kernel_xiaomi_sm8635/releases/tag/v2.1) · [BOOT-NOTES](https://github.com/Mohithash/kernel_xiaomi_sm8635/blob/theettam-premium-sukisu/docs/BOOT-NOTES.md) · [PREMIUM_CHANGELOG](https://github.com/Mohithash/kernel_xiaomi_sm8635/blob/theettam-premium-sukisu/Documentation/theettam/PREMIUM_CHANGELOG.md)
- [droidspaces-v1](https://github.com/Mohithash/kernel_xiaomi_sm8635/releases/tag/droidspaces-v1) · [Droidspaces-OSS](https://github.com/ravindu644/Droidspaces-OSS)
- [SukiSU Ultra](https://github.com/SukiSU-Ultra/SukiSU-Ultra) · [SUSFS](https://gitlab.com/simonpunk/susfs4ksu)
- Wire fix: [a20a40a](https://github.com/Mohithash/kernel_xiaomi_sm8635/commit/a20a40a59f46)

Alpha. Flash at your own risk. Prefer 2.1 if you only need root.