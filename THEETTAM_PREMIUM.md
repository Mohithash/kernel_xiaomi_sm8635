# Theettam Premium (this branch)

Cleanest premium peridot kernel for VoltageOS:

1. **SukiSU-Ultra** + **KPM** (integrated in-tree)
2. **SUSFS v2.2.0** (full hiding stack via official VFS patch path)
3. **Droidspaces-ready** (`CONFIG_USER_NS` + container networking)
4. **BORE + ADIOS + PELT 8ms + Boeffla**

See `Documentation/theettam/PREMIUM.md`.

Root is **committed** on this branch (not CI-time only).

## Modular (Image + modules)

Devs: this branch **makes modules**, not Image-only.

- Full tree: `dist/Theettam-modules-full-*.tar.gz` (`modules_install`)
- Flash extras: AnyKernel `do.modules=1` + `do.systemless=1`
- Docs: `Documentation/theettam/MODULES.md`

