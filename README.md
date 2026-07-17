<div align="center">

<img src="docs/banner.svg" alt="Theettam Kernel — peridot — GKI 6.1.175" width="100%">

<br>

[![Release](https://img.shields.io/github/v/release/Mohithash/kernel_xiaomi_sm8635?style=for-the-badge&label=RELEASE&labelColor=0b1020&color=4f8cff)](../../releases/latest)
[![Kernel](https://img.shields.io/badge/GKI-6.1.175-4ade80?style=for-the-badge&labelColor=0b1020)](https://android.googlesource.com/kernel/common/+/refs/tags/android14-6.1.175_r00)
[![SUSFS](https://img.shields.io/badge/SUSFS-v2.2.0-c084fc?style=for-the-badge&labelColor=0b1020)](https://gitlab.com/simonpunk/susfs4ksu)
[![Downloads](https://img.shields.io/github/downloads/Mohithash/kernel_xiaomi_sm8635/total?style=for-the-badge&label=DOWNLOADS&labelColor=0b1020&color=fbbf24)](../../releases)
[![License](https://img.shields.io/badge/license-GPL--2.0-60a5fa?style=for-the-badge&labelColor=0b1020)](COPYING)
[![Boot tested](https://img.shields.io/badge/all%204%20flavors-boot%20tested-4ade80?style=for-the-badge&labelColor=0b1020)](../../releases/latest)

**A custom GKI kernel for the Xiaomi `peridot` — POCO F6 / Redmi Turbo 3 (Snapdragon 8s Gen 3)**

Four root flavors. Pick the exact root + hiding stack you want.

</div>

---

## <img src="https://img.shields.io/badge/-01-4f8cff?style=flat-square" height="18"> Choose your build

<div align="center">

| Build | Root engine | SUSFS | KPM | Manager | Best for |
|:--|:--|:-:|:-:|:--|:--|
| **KSUN** | KernelSU-Next v3.3.0 | — | — | KernelSU-Next | Lightweight root, no kernel-side hiding |
| **KSUN + SUSFS** ⭐ | KernelSU-Next v3.3.0 | `v2.2.0` | — | KernelSU-Next | Root **+ full hiding** — start here |
| **SukiSU-Ultra + SUSFS** | SukiSU-Ultra | `v2.2.0` | ✅ | SukiSU | Root + hiding **+ Kernel Patch Modules** |
| **ReSukiSU + SUSFS** | ReSukiSU | `v2.2.0` *(native)* | — | ReSukiSU | Root + hiding, **cleanest integration** |

### **[⬇  Download latest](../../releases/latest)**

</div>

> [!NOTE]
> KSUN and SukiSU don't ship kernel-side SUSFS — those builds use a **hand-authored port** written for this
> kernel. ReSukiSU implements SUSFS natively, so its pairing is the cleanest.
> **All four are boot-tested on peridot at 6.1.175**, as is the bare base.

> [!WARNING]
> Flash with a **full backup and fastboot recovery ready**. Back up `boot.img` and `vendor_boot.img` first.

---

## <img src="https://img.shields.io/badge/-02-c084fc?style=flat-square" height="18"> What this fork adds

<table>
<tr><td width="50%" valign="top">

**🐧 Kernel**
- **GKI 6.1.175** — first LTS bump past 6.1.173 for this device
- Real 3-way merge of ACK `android14-6.1-lts` (1010 commits)
- **BORE** CPU scheduler · **ADIOS** I/O scheduler *(default)*

</td><td width="50%" valign="top">

**🛡 Root & hiding**
- **KernelSU-Next v3.3.0 + SUSFS v2.2.0** — a pairing that
  doesn't exist upstream, integrated here
- **SukiSU-Ultra + SUSFS** *(+KPM)* · **ReSukiSU + SUSFS**
- **BBRv3 + PLB** congestion control

</td></tr>
</table>

<details>
<summary><b>🔍 Version reporting — three independent layers</b></summary>

<br>

| Layer | Effect |
|:--|:--|
| `CONFIG_LOCALVERSION` | reports `6.1.175-android14-11-ga3b9c44908dd-ab13320413` — stock GKI form, **no custom kernel branding** |
| `CONFIG_UNAME_OVERRIDE` | `com.google.android.gms` is served `6.1.118-android14-11-ga3b9c44908dd-ab13320413` |
| SUSFS `spoof_uname` | manager-configurable spoofing on top |

`uname -r` showing the real version to your shell is **correct** — the GMS override is targeted by
caller cmdline, and the SUSFS spoof is inert until your manager sets it.

</details>

<details>
<summary><b>🔍 SUSFS features (all SUSFS builds)</b></summary>

<br>

`sus_path` · `sus_mount` · `sus_kstat` · `sus_map` · `spoof_uname` · `spoof_cmdline/bootconfig` ·
`open_redirect` · `hide_ksu_susfs_symbols` · `enable_log`

Drive them from your manager's SUSFS settings, or a SUSFS module.

</details>

<details>
<summary><b>🔍 Tuning inherited from the device base</b></summary>

<br>

Already present in the base this fork builds on, and preserved here — **not this fork's work**:
**MGLRU** · **fq_codel** default qdisc · in-kernel **WireGuard** · **UCLAMP** (task + task-group) ·
**`HZ=300`** · zram (lz4/zstd) · the `UNAME_OVERRIDE` GMS spoof.

</details>

---

## <img src="https://img.shields.io/badge/-03-4ade80?style=flat-square" height="18"> Flashing

```bash
1.  Download the ZIP for your flavor from Releases
2.  Boot to custom recovery, or use the AnyKernel3 flash flow
3.  Flash the ZIP  →  reboot
4.  Install the matching manager app  →  grant root
5.  For hiding: enable SUSFS in the manager, add your targets
```

AnyKernel3 flashes the **`Image` only** — your stock `vendor_dlkm` is kept.

---

## <img src="https://img.shields.io/badge/-04-fbbf24?style=flat-square" height="18"> Building

The kernel source and its CI live on the **[`peridot-6.1.175`](../../tree/peridot-6.1.175)** branch —
`main` carries the docs.

```bash
# all four flavors build from one matrix workflow
.github/workflows/build-theettam-20.yml

# SUSFS integration — hand-port, and the native pairing
scripts/susfs/integrate.sh          # KernelSU-Next
scripts/susfs/integrate-sukisu.sh   # SukiSU-Ultra
scripts/susfs/integrate-native.sh   # ReSukiSU (fs-side only)

# pinned upstreams, checked on the 5th and 20th
upstreams.json  ·  scripts/ci/check-upstreams.py
```

Every upstream is pinned to an exact commit — a moved or reclaimed repo fails the
build loudly instead of quietly building someone else's tree.

---

## <img src="https://img.shields.io/badge/-05-60a5fa?style=flat-square" height="18"> Credits & upstreams

Built on GPL-2.0 upstreams — thanks to their authors:

- **[GuidixX/kernel_xiaomi_sm8635](https://github.com/GuidixX/kernel_xiaomi_sm8635)** — the peridot device
  kernel this fork is built on, and the source of its device support and most of its tuning
- **[LineageOS](https://github.com/LineageOS)** `android_kernel_qcom_sm8650` — qcom/device bits *(retargeted to sm8635)*
- **[Android Common Kernel](https://android.googlesource.com/kernel/common)** `android14-6.1-lts`
- **[BORE](https://github.com/firelzrd/bore-scheduler)** and **ADIOS** by Masahito Suzuki *(firelzrd)*
- **[SUSFS (susfs4ksu)](https://gitlab.com/simonpunk/susfs4ksu)** by simonpunk
- **[KernelSU-Next](https://github.com/KernelSU-Next/KernelSU-Next)** · **[SukiSU-Ultra](https://github.com/SukiSU-Ultra/SukiSU-Ultra)** · **[ReSukiSU](https://github.com/ReSukiSU/ReSukiSU)**
- peridot device kernel source *(Xiaomi)*

<div align="center">
<br>

**Maintainer:** Mohithash *(Theettam Kernel)*
Root/SUSFS builds are provided as-is — flash at your own risk.

<sub>

[Releases](../../releases) · [Telegram post](docs/telegram-post.md) · [Upstream tracker](../../issues)

</sub>
</div>
