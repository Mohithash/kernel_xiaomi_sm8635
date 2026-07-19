# Modular Theettam — “we have kernel but nobody making modules”

## What the complaint means

On modern Android **GKI** devices (peridot / SM8635):

| Piece | Role |
|-------|------|
| `Image` | Core kernel (boot/init_boot) |
| **`.ko` modules** | Most drivers live as loadable modules in `vendor_dlkm` / `system_dlkm` |
| ROM / device tree | Must ship modules that **match** the kernel version + KMI/CRC |

Many custom kernels only flash **Image** via AnyKernel and never:

1. run `modules_install`
2. publish a modules tarball for ROM builders
3. ship optional extras as `.ko` inside the zip

So a dev looking at the tree sees a kernel source… and **no module pipeline**. That is the complaint.

## What stays built-in (`=y`)

These **must not** be modules — they hook too early:

- **SukiSU-Ultra / KPM** (`CONFIG_KSU`, `CONFIG_KPM`)
- **SUSFS** (`CONFIG_KSU_SUSFS` + VFS hooks)

## What is modular (`=m`)

Optional Theettam extras (can update without full reflash when using systemless modules):

- `boeffla_wl_blocker.ko` — wakelock blocker
- `wireguard.ko` — VPN

Stock vendor modules (Wi‑Fi, touch, …) still come from the **ROM’s** `vendor_dlkm`. We keep KMI-friendly so they continue to load against this Image.

## Build outputs

```bash
# full build
bash theettam/scripts/build_theettam.sh

# or after Image already built:
OUT=out bash theettam/scripts/package_modules.sh
```

Artifacts under `dist/`:

| Artifact | Who uses it |
|----------|-------------|
| `Theettam-modules-full-*.tar.gz` | ROM/devs rebuilding `vendor_dlkm` / `system_dlkm` |
| `Theettam-modules-extras-*.tar.gz` | Optional extras only |
| AnyKernel zip | Image + extras under `modules/` (`do.modules=1`, `do.systemless=1`) |

## Flash behaviour

- `do.modules=1` + `do.systemless=1` → AK3 installs extras via Magisk / KernelSU(SukiSU) **ak3-helper** module (no vendor remount required).
- Full dlkm replacement is a **ROM** job using the full tarball — not the daily flash zip.

## CI

`build-premium-sukisu.yml` builds Image, runs `package_modules.sh`, uploads:

- kernel zip
- full modules tarball
- extras tarball
