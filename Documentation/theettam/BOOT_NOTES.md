# Boot / bootloop notes (peridot)

## Alpha-1 stuck on Poco logo — root cause

Same class of failure as early Droidspaces builds on `peridot-6.1.175`:

1. **`CONFIG_CGROUP_DEVICE` / `CONFIG_CGROUP_PIDS`** resize `css_set` → shift
   genksyms CRC of nearly everything with `task_struct*` → **vendor modules refuse
   to load** (display, touch, UFS) → hang on logo. (commit `f37c68f464`)

2. **`CONFIG_BRIDGE_NETFILTER` / `CONFIG_NF_TABLES`** break CRCs across
   `kernel/sched/core.c` exports (wake_up_process, etc.) → second bootloop.
   (commit `88c1263bc9`)

Alpha-1 `theettam_GKI.config` re-enabled (1) and (2) via “research 100%”
container matrix. **That was wrong for GKI+stock vendor_dlkm.**

## Alpha-2 policy

- Keep **USER_NS / PID_NS / SYSVIPC / basic NAT / veth** (namespace isolation).
- **Never** enable CGROUP_DEVICE, CGROUP_PIDS, BRIDGE_NETFILTER, NF_TABLES
  unless you also rebuild all vendor modules or disable version checks.
- Flash **Image-only** AnyKernel (`do.modules=0`) like bootable v2.1 zips.
- Reference bootable release: **v2.1** tag / Theettam 2.0 CI on peridot-6.1.175.

## If still stuck on logo

1. Reflash **v2.1** or last known good zip to recover.
2. Capture `adb wait-for-device; adb shell dmesg` after recovery boot if possible.
3. Do not enable the forbidden configs “to make Docker complete”.
