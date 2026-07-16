# Theettam Kernel — POCO F6 / Redmi Turbo 3 (peridot, SM8635)

A custom **GKI `android14-6.1.173`** kernel for the Xiaomi **peridot** (POCO F6 / Redmi Turbo 3,
Snapdragon 8s Gen 3), tuned for performance and battery, and shipped in **four root flavors** so
you can pick the exact root + hiding stack you want.

> All four boot on peridot. The SUSFS variants pair the latest **SUSFS v2.2.0** with the current
> KernelSU-family drivers — including combinations that did not exist upstream and were integrated
> for this kernel.

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

## Kernel tuning (all builds)

- **Networking:** BBRv3 congestion control + **fq_codel** default qdisc (low bufferbloat), in-kernel **WireGuard**
- **Memory:** **MGLRU** (multi-gen LRU, on by default), zram with lz4/zstd, cleancache
- **Scheduler:** UCLAMP (task + task-group), `HZ=300`
- **Power:** PM/thermal cleanups, `init_on_free` disabled for lower overhead

---

## Flashing

1. Download the ZIP for your chosen build from [Releases](../../releases).
2. Boot to a custom recovery (or use the AnyKernel3 flash flow) — the ZIP is **AnyKernel3** based.
3. Flash the ZIP, reboot.
4. Install the matching **manager app** (KernelSU-Next / SukiSU / ReSukiSU) and grant root.
5. For hiding: enable **SUSFS** in the manager (or install a SUSFS module) and add your targets.

**Always keep a backup of your current boot/init_boot and be ready for fastboot recovery.**

---

## Credits & upstreams

Built on GPL-2.0 upstreams — thanks to their authors:

- **KernelSU-Next** — <https://github.com/KernelSU-Next/KernelSU-Next>
- **SukiSU-Ultra** — <https://github.com/ShirkNeko/SukiSU-Ultra>
- **ReSukiSU** — <https://github.com/ReSukiSU/ReSukiSU>
- **SUSFS (susfs4ksu)** by simonpunk — <https://gitlab.com/simonpunk/susfs4ksu>
- peridot device kernel source (Xiaomi) + Android Common Kernel `android14-6.1`

The SUSFS integration scripts for the driver-agnostic hand-port (`scripts/susfs/integrate.sh`)
and the native pairing (`scripts/susfs/integrate-native.sh`) live in this tree, along with the
per-build CI workflows under `.github/workflows/`.

*Maintainer: Mohithash (Theettam Kernel). Root/SUSFS builds are provided as-is; flash at your own risk.*
