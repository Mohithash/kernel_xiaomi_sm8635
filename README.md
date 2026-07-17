# Theettam Kernel — POCO F6 / Redmi Turbo 3 (peridot, SM8635)

A custom **GKI `android14-6.1.175`** kernel for the Xiaomi **peridot** (POCO F6 / Redmi Turbo 3,
Snapdragon 8s Gen 3), tuned for performance and battery, and shipped in **four root flavors** so
you can pick the exact root + hiding stack you want.

> **6.1.175** — the first LTS bump past 6.1.173 for this device, done as a real 3-way merge of the
> Android Common Kernel `android14-6.1-lts` branch. All four flavors pair the latest **SUSFS v2.2.0**
> with current KernelSU-family drivers — including combinations that did not exist upstream and
> were integrated for this kernel.

---

## Choose your build

| Build | Root engine | SUSFS | KPM | Manager app | Best for |
|---|---|:---:|:---:|---|---|
| **KSUN** | KernelSU-Next v3.3.0 | — | — | KernelSU-Next | Lightweight root, no kernel-side hiding |
| **KSUN + SUSFS** | KernelSU-Next v3.3.0 | ✅ v2.2.0 | — | KernelSU-Next | Root **+ full hiding** |
| **SukiSU-Ultra + SUSFS** | SukiSU-Ultra | ✅ v2.2.0 | ✅ | SukiSU | Root + hiding **+ Kernel Patch Modules** |
| **ReSukiSU + SUSFS** | ReSukiSU | ✅ v2.2.0 *(native)* | — | ReSukiSU | Root + hiding, **cleanest integration** |

**Quick guidance**
- **Just want root, minimal footprint?** → **KSUN**
- **Root + hide from detection (banking, integrity, etc.)?** → any SUSFS build
- **Want runtime Kernel Patch Modules (`.kpm`)?** → **SukiSU-Ultra + SUSFS**
- **Want the most robust SUSFS (driver ships it natively, no hand-port)?** → **ReSukiSU + SUSFS**

> The KSUN and SukiSU SUSFS builds integrate SUSFS via a hand-authored port (their drivers don't
> ship kernel-side SUSFS). ReSukiSU implements SUSFS natively, so its pairing is the cleanest.
> Flash any build with a **full backup and fastboot recovery ready**.

---

## SUSFS features (all SUSFS builds)

SUSFS **v2.2.0** with: `sus_path`, `sus_mount`, `sus_kstat`, `sus_map`, `spoof_uname`,
`spoof_cmdline/bootconfig`, `open_redirect`, and `hide_ksu_susfs_symbols`. Drive it via your
manager app's SUSFS settings (or a SUSFS module).

## Version reporting

The kernel reports a **stock GKI version string** rather than a custom kernel name, and GMS is
served a certified-looking release:

| Layer | Effect |
|---|---|
| `CONFIG_LOCALVERSION` | reports `6.1.175-android14-11-ga3b9c44908dd-ab13320413` — stock GKI form, no custom branding |
| `CONFIG_UNAME_OVERRIDE` | `com.google.android.gms` is served `6.1.118-android14-11-ga3b9c44908dd-ab13320413` |
| SUSFS `spoof_uname` | manager-configurable uname spoofing on top |

---

## What this fork adds

On top of the peridot device base (see Credits):

- **6.1.175** — full ACK `android14-6.1-lts` merge (1010 commits; conflicts resolved toward the device side)
- **BORE** CPU scheduler — `sysctl kernel.sched_bore=0` disables it at runtime
- **ADIOS** I/O scheduler (default)
- **BBRv3** congestion control + **PLB** (protective load balancing)
- **Stock GKI version string** in place of the base's custom kernel name
- **`MODULE_SIG=n`** so KernelSU-family modules load
- The **four root flavors** above, including the SUSFS ports and their CI

## Tuning inherited from the device base

Already present in the base this fork builds on, and preserved here: **MGLRU** (multi-gen LRU),
**fq_codel** default qdisc, in-kernel **WireGuard**, **UCLAMP** (task + task-group), **`HZ=300`**,
zram (lz4/zstd), and the `UNAME_OVERRIDE` GMS spoof.

---

## Flashing

1. Download the ZIP for your chosen build from [Releases](../../releases).
2. Boot to a custom recovery (or use the AnyKernel3 flash flow) — the ZIP is **AnyKernel3** based.
3. Flash the ZIP, reboot.
4. Install the matching **manager app** (KernelSU-Next / SukiSU / ReSukiSU) and grant root.
5. For hiding: enable **SUSFS** in the manager (or install a SUSFS module) and add your targets.

AnyKernel3 flashes the `Image` only — your stock `vendor_dlkm` is kept.

**Always keep a backup of your current boot/init_boot and be ready for fastboot recovery.**

---

## Credits & upstreams

Built on GPL-2.0 upstreams — thanks to their authors:

- **GuidixX/kernel_xiaomi_sm8635** — the peridot device kernel this fork is built on, and the source
  of its device support and most of its tuning — <https://github.com/GuidixX/kernel_xiaomi_sm8635>
- **LineageOS** `android_kernel_qcom_sm8650` — qcom/device bits (retargeted to sm8635)
- **Android Common Kernel** `android14-6.1-lts` — <https://android.googlesource.com/kernel/common>
- **BORE** (Burst-Oriented Response Enhancer) and **ADIOS** (Adaptive Deadline I/O Scheduler) by
  Masahito Suzuki (firelzrd) — <https://github.com/firelzrd/bore-scheduler>
- **SUSFS (susfs4ksu)** by simonpunk — <https://gitlab.com/simonpunk/susfs4ksu>
- **KernelSU-Next** — <https://github.com/KernelSU-Next/KernelSU-Next>
- **SukiSU-Ultra** — <https://github.com/ShirkNeko/SukiSU-Ultra>
- **ReSukiSU** — <https://github.com/ReSukiSU/ReSukiSU>
- peridot device kernel source (Xiaomi)

The SUSFS integration scripts — the hand-port (`scripts/susfs/integrate.sh`,
`scripts/susfs/integrate-sukisu.sh`) and the native pairing (`scripts/susfs/integrate-native.sh`) —
live in this tree, along with the per-build CI workflows under `.github/workflows/`.

*Maintainer: Mohithash (Theettam Kernel). Root/SUSFS builds are provided as-is; flash at your own risk.*
