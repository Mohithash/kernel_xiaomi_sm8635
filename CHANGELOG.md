# Changelog: `sukisu-ultra-susfs` branch

Base: `GuidixX/kernel_xiaomi_sm8635` branch `16.2` @ `209fbd25e`
("power: supply: qti_battery_charger: Remove fastcharge mode caching to prevent sticky slow charging")

2 commits, 671 files changed (636 of which are SukiSU-Ultra's own vendored
driver source tree, added wholesale; the rest are modifications to existing
kernel files plus 4 new susfs core files).

Confirmed booting and SukiSU/susfs detection working on real hardware
(POCO F6 / peridot, VoltageOS) at this exact state.

## 1. Cherry-picked upstream fix

- `9ad4326` — disable module signing in `gki_defconfig` (from GuidixX's own
  `gki` branch)

## 2. SUSFS integration (`susfs4ksu`, branch `gki-android14-6.1`)

New files: `fs/susfs.c`, `include/linux/susfs.h`, `include/linux/susfs_def.h`

Modified for the VFS-level hooks (sus_path, sus_mount, sus_kstat,
spoof_uname, sus_map, open_redirect, AVC log spoofing):
`fs/exec.c`, `fs/namei.c`, `fs/namespace.c`, `fs/notify/fdinfo.c`,
`fs/open.c`, `fs/proc/{base,bootconfig,fd,task_mmu}.c`,
`fs/proc_namespace.c`, `fs/read_write.c`, `fs/readdir.c`, `fs/stat.c`,
`fs/statfs.c`, `kernel/{kallsyms,reboot,sys}.c`, `mm/memory.c`,
`security/selinux/{avc,hooks,selinuxfs}.c`, `drivers/input/input.c`,
`fs/Makefile`

Manual fixes for two Xiaomi vendor-patch conflicts the official susfs
patch didn't anticipate:
- a perf-optimized rewrite of `show_map_vma()` in `fs/proc/task_mmu.c`
- an extra vendor `#include` in `fs/namespace.c`

Two now-obsolete susfs calls removed (mount-ID reordering and an SD-card
root-path setter) — both superseded by automatic mechanisms in the
current susfs core, calling them would have referenced removed functions.

Anti-detection extras (fake-SELinux-enforcing-status, init.rc read/fstat
spoofing, input-event hook) stubbed inert rather than ported, since they
require the newer KSU core/feature/hook architecture that this build
doesn't otherwise use.

## 3. SukiSU-Ultra v4.1.3 (`KernelSU/`, vendored whole)

Wired in via `drivers/kernelsu` symlink, `drivers/Kconfig`/`drivers/Makefile`.

**Real upstream bugs in v4.1.3 itself, found and fixed:**

- `Kbuild` was missing object-file entries for source files that are
  already called from elsewhere in the tree: `hook/lsm_hook.c`,
  `hook/syscall_hook_manager.c`, `hook/syscall_event_bridge.c`,
  `hook/tp_marker.c`, `hook/arm64/patch_memory.c`,
  `infra/symbol_resolver.c`. None of this is susfs-related — a
  completely vanilla v4.1.3 build would hit the same link errors.
- Dangling reference to a `ksu_late_loaded` variable that doesn't exist
  anywhere in the codebase (`core/init.c`) — removed; this build is
  always statically built-in, never late-loaded, so the branch was dead
  regardless.
- Undeclared-variable bug (`for_each_thread(p, t)` with neither declared)
  in `escape_with_root_profile()` (`policy/app_profile.c`).
- **`apply_kernelsu_rules()` / `cache_sid()` / `setup_ksu_cred()` were
  unreachable** after an earlier fix orphaned their only caller.
  Restored via a reimplemented init.rc-second-stage detector in
  `hook/syscall_event_bridge.c`. Without this, every susfs SID check
  (`susfs_zygote_sid`/`susfs_ksu_sid`/etc, all stuck at 0) silently
  no-ops, and the manager app can never get its communication fd
  installed — this is what "SukiSU Ultra not installed" in the manager
  app traced back to.
- Dangling calls into the new-architecture sucompat rewrite (never
  ported) removed from `fs/exec.c`, `fs/stat.c`, `fs/open.c`,
  `hook/syscall_event_bridge.c`; SukiSU's existing native su-hiding
  mechanism already covers the same functionality.
- Argument-count/signature mismatch on `ksu_handle_setresuid()` calls
  (old 2-arg call site against the current 3-arg signature), plus a
  missing header declaration for the same function.

`KSU_VERSION` pinned to `40796` at build time. `Kbuild` computes this by
default from a live GitHub API commit-count query against `main` at
build time, not from the checked-out tag, which drifted from what the
`v4.1.3`-tagged manager app actually expects (`40811` vs `40796`).

## 4. Config

- `CONFIG_KSU=y`, `CONFIG_KSU_SUSFS=y` plus the six susfs feature flags
  (sus_path, sus_mount, sus_kstat, spoof_uname, open_redirect, sus_map)
- `CONFIG_KPM=y` (SukiSU's runtime kernel-patch loader)

## 5. Packaging

- `anykernel.sh`: `patch_vbmeta_flag` forced to `1`. The default `auto`
  only preserves whatever vbmeta flag state was already present rather
  than actively disabling verification, which doesn't work against
  VoltageOS's strict AVB enforcement (`BOARD_AVB_ENABLE := true` with
  rollback indices on both the boot and recovery chains).
- AnyKernel zips package the bare uncompressed `Image`, not `Image.gz`.
  `magiskboot repack` re-compresses whatever's in the working "kernel"
  file to match the target boot image's format; feeding it an
  already-gzipped image risks double-compression and a corrupt kernel.

## 6. Hardening against root/SUSFS detection bypasses

- `CONFIG_IKCONFIG_PROC` disabled — `/proc/config.gz` previously leaked
  the running defconfig in plaintext, including `CONFIG_KSU=y` /
  `CONFIG_KSU_SUSFS=y`.
- `CONFIG_KALLSYMS_ALL` disabled — shrinks what's exposed via
  `/proc/kallsyms` to apps scanning for `ksu_*`/`susfs_*` symbol names.
  SukiSU's own internal symbol resolver (`infra/symbol_resolver.c`) uses
  `kallsyms_lookup_name()` against the full compiled-in symbol table,
  which is unaffected by this — only the userspace-visible table shrinks.
- `CONFIG_SECURITY_DMESG_RESTRICT=y` — blocks unprivileged `dmesg`/
  `/dev/kmsg` reads, which could otherwise leak KSU/SUSFS init log lines.
- `kptr_restrict` (`lib/vsprintf.c`) default changed from `0` to `2` —
  kernel pointers are hidden from all unprivileged readers by default
  instead of requiring a runtime sysctl.
- `build.sh`: `KBUILD_BUILD_USER`/`KBUILD_BUILD_HOST` now pinned to
  generic values (`build`/`localhost`) instead of leaking
  `root@<container-hostname>` into `/proc/version` via the default
  `whoami`/`uname -n` fallback.
- `build.sh`: fixed packaging bug copying `Image.gz` into the AnyKernel
  zip instead of the bare uncompressed `Image` (see §5 above for why
  this matters — was already documented but not actually applied here).

## Explicitly not included

- **TCP Brutal, CAKE, BBR2** were added and iterated on in a later round
  but never flash-tested on real hardware, unlike everything above.
  BBR2 specifically does not fit this kernel's `skb->cb[]` budget without
  removing something else already using that space (hand-verified via
  struct alignment math, confirmed twice with failed builds) — its
  `tx_in_flight`/`lost` fields require per-packet state in
  `struct tcp_skb_cb` that exceeds the kernel's documented 24-byte
  `tx` slot, and was never merged into mainline Linux even by Google's
  own team, who moved on to BBR v3 without this mechanism.
