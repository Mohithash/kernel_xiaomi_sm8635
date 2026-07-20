<div align="center">

# Theettam Premium Alpha
### SukiSU Ultra · KPM · SUSFS · DroidSpaces (KABI-safe)
**peridot** · POCO F6 / Redmi Turbo 3 · GKI **6.1.175**

[![Status](https://img.shields.io/badge/status-alpha-fbbf24?style=for-the-badge&labelColor=0b1020)](https://github.com/Mohithash/kernel_xiaomi_sm8635/releases/tag/theettam-premium-alpha-175-ksu)
[![GKI](https://img.shields.io/badge/GKI-6.1.175-4ade80?style=for-the-badge&labelColor=0b1020)](https://android.googlesource.com/kernel/common/+/refs/tags/android14-6.1.175_r00)
[![Base](https://img.shields.io/badge/base-Theettam%202.1%20line-4f8cff?style=for-the-badge&labelColor=0b1020)](https://github.com/Mohithash/kernel_xiaomi_sm8635/releases/tag/v2.1)
[![Root](https://img.shields.io/badge/root-SukiSU%20Ultra%20%2B%20KPM-c084fc?style=for-the-badge&labelColor=0b1020)](https://github.com/SukiSU-Ultra/SukiSU-Ultra)
[![Hide](https://img.shields.io/badge/hide-SUSFS%20v2.2.0-a78bfa?style=for-the-badge&labelColor=0b1020)](https://gitlab.com/simonpunk/susfs4ksu)
[![Containers](https://img.shields.io/badge/containers-DroidSpaces%20safe-f472b6?style=for-the-badge&labelColor=0b1020)](https://github.com/ravindu644/Droidspaces-OSS)

**One Image. Stock `vendor_dlkm`. Hard Module.symvers gate.**  
Commit [`a20a40a59f46`](https://github.com/Mohithash/kernel_xiaomi_sm8635/commit/a20a40a59f46) · built on ServerHive · uname `6.1.175-android14-11-ga3b9c44908dd-ab13320413`

</div>

---

## Download

| Asset | Notes |
|:--|:--|
| **[Theettam-Premium-SukiSU-KSU-FIXED-…-a20a40a59f46-20260720-0241.zip](https://github.com/Mohithash/kernel_xiaomi_sm8635/releases/download/theettam-premium-alpha-175-ksu/Theettam-Premium-SukiSU-KSU-FIXED-peridot-6.1.175-android14-11-ga3b9c44908dd-ab13320413-a20a40a59f46-20260720-0241.zip)** | **Flash this** — `CONFIG_KSU=y` wired |

> [!CAUTION]
> Do **not** use the older tag [`theettam-premium-alpha-175-kabi`](https://github.com/Mohithash/kernel_xiaomi_sm8635/releases/tag/theettam-premium-alpha-175-kabi). That Image **booted but had no root** (`CONFIG_KSU` never enabled). This release is the fix: [`a20a40a`](https://github.com/Mohithash/kernel_xiaomi_sm8635/commit/a20a40a59f46) wires `drivers/kernelsu` and fails the build if KSU is off.

---

## Why this is a *Premium* build

**Theettam 2.1** is the stable product line: four root flavors, boot-confirmed, July CLO security/vendor refresh — choose KSUN / KSUN+SUSFS / SukiSU / ReSukiSU and go.

**Theettam Premium** is a **single, research-backed stack** for users who want the **maximum safe feature set on one Image**, without breaking GKI vendor modules:

| Premium pillar | What you get | Why it is “premium” (not default 2.1) |
|:--|:--|:--|
| **1. Full root stack on one zip** | [SukiSU Ultra](https://github.com/SukiSU-Ultra/SukiSU-Ultra) + **KPM** + [SUSFS v2.2.0](https://gitlab.com/simonpunk/susfs4ksu) | 2.1 ships SukiSU+SUSFS+KPM as *one of four* flavors; Premium is purpose-built around that stack only |
| **2. DroidSpaces (safe)** | LXC-style containers ([Droidspaces-OSS](https://github.com/ravindu644/Droidspaces-OSS)) with **KABI-safe** `SYSVIPC` relocation | Not in main [v2.1](https://github.com/Mohithash/kernel_xiaomi_sm8635/releases/tag/v2.1) assets — proven path from [`droidspaces-v1`](https://github.com/Mohithash/kernel_xiaomi_sm8635/releases/tag/droidspaces-v1) research |
| **3. Category A tunings** | PELT half-life **8 ms**, ZRAM multi-comp, name-only `qcom_rx_wakelock` filter | Extra scheduler/IO power polish on top of 2.1’s BORE/ADIOS/BBRv3 base — **CRC-safe** constants only ([changelog](https://github.com/Mohithash/kernel_xiaomi_sm8635/blob/theettam-premium-sukisu/Documentation/theettam/PREMIUM_CHANGELOG.md)) |
| **4. Hard KABI gate** | Baseline vs premium `Module.symvers` CRC check **required** before ship | GKI freezes KMI; wrong configs = compile-clean **bootloop**. Gate encodes lessons from [BOOT-NOTES](https://github.com/Mohithash/kernel_xiaomi_sm8635/blob/theettam-premium-sukisu/docs/BOOT-NOTES.md) |
| **5. Forbidden-config discipline** | `CGROUP_DEVICE` / `CGROUP_PIDS` / `NF_TABLES` / `BRIDGE_NETFILTER` forced **off** | Those options **bootlooped** DroidSpaces experiments by shifting `task_struct` / sched export CRCs — measured, not guessed ([droidspaces-v1 notes](https://github.com/Mohithash/kernel_xiaomi_sm8635/releases/tag/droidspaces-v1)) |

In one sentence:

> **Premium = Theettam 2.1-line base + SukiSU Ultra/KPM/SUSFS + KABI-safe DroidSpaces + Category A tunings + automated Module.symvers gate — Image-only, stock vendor modules.**

It is **not** “more overclock.” It is **more integrated capability with research-backed boot safety.**

---

## Perfect difference map — Premium vs Theettam 2.1

| | **Theettam 2.1** ([`v2.1`](https://github.com/Mohithash/kernel_xiaomi_sm8635/releases/tag/v2.1)) | **Theettam Premium** (this release) |
|:--|:--|:--|
| **Maturity** | **Stable** Latest | **Alpha** prerelease |
| **Audience** | Everyone — pick a flavor | Power users wanting containers + SukiSU + tunings in one Image |
| **Base kernel** | `6.1.175` + [July CLO / GuidixX refresh](https://github.com/Mohithash/kernel_xiaomi_sm8635/commit/8825c91b918b57031f84602042791df78bfa1766) + ASB | **Same lineage** (Premium is **+6 commits** on 2.1-line base; not a 173 rebuild) |
| **Uname family** | `6.1.175-android14-11-ga3b9c44908dd-…` | Same GKI id family |
| **Root flavors** | **4 zips**: KSUN · KSUN+SUSFS · SukiSU+KPM+SUSFS · ReSukiSU | **1 zip**: SukiSU Ultra + KPM + SUSFS only |
| **Closest 2.1 zip** | [`Theettam-2.1-SukiSU-Ultra-SUSFS2.2.0-KPM-…`](https://github.com/Mohithash/kernel_xiaomi_sm8635/releases/download/v2.1/Theettam-2.1-SukiSU-Ultra-SUSFS2.2.0-KPM-peridot-6.1.175-android14-11-ga3b9c44908dd-ab13320413.zip) | This asset ≈ that **plus** DroidSpaces + Category A + gate |
| **SUSFS** | v2.2.0 ([simonpunk/susfs4ksu](https://gitlab.com/simonpunk/susfs4ksu)) | v2.2.0 pin `@8199bb65` + 175 `namespace.c` pre-apply fix |
| **KPM** | Yes (SukiSU flavor) | Yes (`CONFIG_KPM=y`) |
| **DroidSpaces** | ❌ not in main 2.1 assets | ✅ **safe set** (no fatal cgroup/netfilter KABI breaks) |
| **Category A** | Base BORE / ADIOS / BBRv3 / MGLRU only | + PELT 8 ms · ZRAM multi-comp · wakelock name filter |
| **KABI process** | Boot-tested product release | Hard **Module.symvers** CRC gate in build script |
| **Flash** | Image-only AnyKernel · keep stock `vendor_dlkm` | Same contract |
| **Manager** | Match flavor (KSUN / SukiSU / ReSukiSU) | **SukiSU Ultra only** — uninstall other KSU managers |
| **When to use** | Daily driver, multi-flavor choice | One Image: root + hide + KPM + containers + tunings |

### ASCII stack (what each layer adds)

```text
┌─────────────────────────────────────────────────────────────┐
│  PREMIUM extras                                              │
│  • DroidSpaces (safe / SYSVIPC via KABI reserve slots)     │
│  • Category A: PELT 8ms, ZRAM multi-comp, WL name filter   │
│  • Module.symvers CRC gate + forbidden configs forced off  │
│  • SukiSU wire fix (CONFIG_KSU=y + drivers/kernelsu)       │
├─────────────────────────────────────────────────────────────┤
│  Same as 2.1 SukiSU flavor                                  │
│  • SukiSU Ultra + KPM + SUSFS v2.2.0                        │
│  • BORE · ADIOS · BBRv3 · MGLRU (base)                      │
├─────────────────────────────────────────────────────────────┤
│  Shared Theettam 2.1 / peridot-6.1.175 foundation           │
│  • GKI android14-6.1.175 + July CLO vendor refresh          │
│  • Image-only flash · stock vendor_dlkm · boot-safety reverts│
└─────────────────────────────────────────────────────────────┘
```

---

## Linked research (source of truth)

Every Premium decision is grounded in prior on-device / tree research — not vibes.

| Topic | Research / source | How Premium uses it |
|:--|:--|:--|
| **Boot vs compile** | [docs/BOOT-NOTES.md](https://github.com/Mohithash/kernel_xiaomi_sm8635/blob/theettam-premium-sukisu/docs/BOOT-NOTES.md) | Never rebuild from old 173 base; start from `peridot-6.1.175` |
| **KABI / genksyms** | BOOT-NOTES Rule 1–2 · [droidspaces-v1](https://github.com/Mohithash/kernel_xiaomi_sm8635/releases/tag/droidspaces-v1) | Forbidden cgroup/netfilter configs; CRC gate before flash |
| **DroidSpaces bootloops** | [droidspaces-v1 release notes](https://github.com/Mohithash/kernel_xiaomi_sm8635/releases/tag/droidspaces-v1) · [Droidspaces-OSS](https://github.com/ravindu644/Droidspaces-OSS) | Safe config only; `SYSVIPC` via `ANDROID_KABI_RESERVE` relocation (`scripts/droidspaces/integrate.sh`) |
| **Premium change catalog** | [PREMIUM_CHANGELOG.md](https://github.com/Mohithash/kernel_xiaomi_sm8635/blob/theettam-premium-sukisu/Documentation/theettam/PREMIUM_CHANGELOG.md) | Category A / B / C tables |
| **Premium config fragment** | [theettam_premium.config](https://github.com/Mohithash/kernel_xiaomi_sm8635/blob/theettam-premium-sukisu/theettam/configs/theettam_premium.config) | ZRAM multi-comp; forbidden options documented off |
| **Stable product baseline** | [Theettam Kernel 2.1](https://github.com/Mohithash/kernel_xiaomi_sm8635/releases/tag/v2.1) · commit [8825c91b](https://github.com/Mohithash/kernel_xiaomi_sm8635/commit/8825c91b918b57031f84602042791df78bfa1766) | July CLO + ASB + four flavors |
| **SukiSU Ultra** | [SukiSU-Ultra/SukiSU-Ultra](https://github.com/SukiSU-Ultra/SukiSU-Ultra) · pin `susfs_new` `@278d822a` | Root + KPM manager pairing |
| **SUSFS** | [simonpunk/susfs4ksu](https://gitlab.com/simonpunk/susfs4ksu) · pin `@8199bb65` | Kernel-side hide; 175 namespace pre-apply |
| **GKI / KMI freeze** | [Android GKI overview](https://source.android.com/docs/core/architecture/kernel/generic-kernel-image) · ACK [android14-6.1.175](https://android.googlesource.com/kernel/common/+/refs/tags/android14-6.1.175_r00) | Why Image-only + stock `vendor_dlkm` is mandatory |
| **KSU wire fix** | commit [a20a40a](https://github.com/Mohithash/kernel_xiaomi_sm8635/commit/a20a40a59f46) | `drivers/kernelsu` link + `CONFIG_KSU=y` hard fail |
| **Device base / CLO** | GuidixX merge into 175 · [v2.1 notes](https://github.com/Mohithash/kernel_xiaomi_sm8635/releases/tag/v2.1) | Security + vendor driver refresh under Premium |

> [!IMPORTANT]
> **“100% full DroidSpaces research config” is intentionally NOT claimed.** Full DroidSpaces wishlists that enable `CGROUP_DEVICE`/`PIDS` or `NF_TABLES`/`BRIDGE_NETFILTER` **bootlooped** on this device. Premium ships the **verified-safe subset** only. See [droidspaces-v1](https://github.com/Mohithash/kernel_xiaomi_sm8635/releases/tag/droidspaces-v1) and [BOOT-NOTES](https://github.com/Mohithash/kernel_xiaomi_sm8635/blob/theettam-premium-sukisu/docs/BOOT-NOTES.md).

---

## What’s inside this Image

### Root & hide (Category B)
- **SukiSU Ultra** (`CONFIG_KSU=y`) + **KPM** (`CONFIG_KPM=y`)
- **SUSFS v2.2.0** options enabled in build (path/mount/kstat/map/open_redirect/uname/cmdline spoof paths as integrated)
- Pins: SukiSU `278d822a` · SUSFS `8199bb65`

### Containers (Category B, safe)
- **DroidSpaces** integration with **no** `CONFIG_CGROUP_DEVICE` / `CONFIG_CGROUP_PIDS`
- **no** `CONFIG_NF_TABLES` / `CONFIG_BRIDGE_NETFILTER`
- `SYSVIPC` only with KABI reserve-slot relocation (BOOT-NOTES Rule 1)

### Tunings (Category A — expect core-safe CRCs)
- PELT half-life **8 ms** (`LOAD_AVG_PERIOD` / `LOAD_AVG_MAX` constants)
- **ZRAM** multi-comp / LZ4 default / writeback fragment
- Name-only block for **`qcom_rx_wakelock`** (layout-safe; not struct surgery)
- Base already carries **BORE**, **ADIOS**, **BBRv3**, **MGLRU** from 2.1 line

### Packaging contract
- AnyKernel3 · **`Image` only** · `do.modules=0`
- **Keep stock `vendor_dlkm`**
- Kernel string: `Theettam-Premium-SukiSU-KSU-FIXED`

---

## Install

1. **Backup** `boot` (and preferably `vendor_boot`) — keep fastboot + [OrangeFox](https://orangefox.download/) recovery ready.
2. Flash the **KSU-FIXED** zip (recovery sideload or file install).
3. Install **only** the **[SukiSU Ultra](https://github.com/SukiSU-Ultra/SukiSU-Ultra/releases)** manager.  
   Uninstall KernelSU-Next / ReSukiSU / Magisk managers that fight crowning (see [v2.0 multi-manager note](https://github.com/Mohithash/kernel_xiaomi_sm8635/releases/tag/v2.0)).
4. Reboot → open SukiSU Ultra → grant apps as needed.

```bash
# optional after first boot (USB debugging)
adb shell uname -a
# expect: 6.1.175-android14-11-ga3b9c44908dd …
adb shell su -c id
```

### Prefer stable instead?
Use **[Theettam 2.1](https://github.com/Mohithash/kernel_xiaomi_sm8635/releases/tag/v2.1)** — especially the SukiSU Ultra flavor if you want root without DroidSpaces/Category A.

---

## Changelog (this tag)

| Commit | Summary |
|:--|:--|
| [`a20a40a`](https://github.com/Mohithash/kernel_xiaomi_sm8635/commit/a20a40a59f46) | **fix:** wire `drivers/kernelsu` + require `CONFIG_KSU=y` (root actually works) |
| [`9443c391`](https://github.com/Mohithash/kernel_xiaomi_sm8635/commit/9443c391366b) | SUSFS namespace pre-apply for 6.1.175 `blk.h` layout |
| premium rebuild commits | Branch from 175 only · Category A/B · KABI gate · BTF off for CI · BOOT-NOTES |

Full catalog: [PREMIUM_CHANGELOG.md](https://github.com/Mohithash/kernel_xiaomi_sm8635/blob/theettam-premium-sukisu/Documentation/theettam/PREMIUM_CHANGELOG.md)

---

## Disclaimer

Alpha software. Flash at your own risk. Image-only design preserves vendor modules, but **any** custom kernel can hard-brick recovery paths if you flash the wrong package or lose fastboot. Prefer 2.1 for production daily drive unless you specifically need Premium features.

<div align="center">
<sub>
Built from <code>a20a40a59f46</code> · base family <a href="https://github.com/Mohithash/kernel_xiaomi_sm8635/releases/tag/v2.1">Theettam 2.1 / peridot-6.1.175</a> ·
research: <a href="https://github.com/Mohithash/kernel_xiaomi_sm8635/blob/theettam-premium-sukisu/docs/BOOT-NOTES.md">BOOT-NOTES</a> ·
<a href="https://github.com/Mohithash/kernel_xiaomi_sm8635/releases/tag/droidspaces-v1">DroidSpaces v1</a> ·
<a href="https://github.com/SukiSU-Ultra/SukiSU-Ultra">SukiSU Ultra</a> ·
<a href="https://gitlab.com/simonpunk/susfs4ksu">SUSFS</a> ·
<a href="https://github.com/ravindu644/Droidspaces-OSS">Droidspaces-OSS</a>
</sub>
</div>