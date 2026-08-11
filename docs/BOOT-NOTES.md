# Making this kernel BOOT — hard-won notes (read before touching the tree)

Every rule here comes from a build that compiled cleanly and then **bootlooped**.
On GKI, **a clean compile proves almost nothing about booting.** The bar is: does
the kernel load the device's prebuilt vendor modules? If not → bootloop.

## Rule 0 — build ON the boot-confirmed tree, do not rebuild from scratch

The boot-confirmed base is **`peridot-6.1.175`** (SUBLEVEL **175**, GKI
`android14-6.1.175` + GuidixX July CLO vendor refresh + our delta). It **already
builds** these flavors, boot-tested:

- KernelSU-Next v3.3.0 (+ SUSFS v2.2.0)
- **SukiSU-Ultra + SUSFS v2.2.0**
- ReSukiSU + SUSFS v2.2.0
- **KSUN + SUSFS + DroidSpaces** (LXC containers)

Branching from an OLD base (e.g. `209fbd25`, SUBLEVEL 173) and hand-re-integrating
SukiSU/SUSFS/network patches is how you get a non-booting kernel. It throws away
the 175 LTS, the July security/vendor fixes, and every proven integration. **Start
from `peridot-6.1.175`.** The build matrix is `.github/workflows/build-theettam-20.yml`.

## Rule 1 — KABI is the #1 boot-killer (compile-clean, boot-dead)

GKI freezes the KMI. Vendor modules (display/touch/camera/UFS in `vendor_dlkm`) are
**prebuilt binaries** we do NOT rebuild. If a config change alters a struct in the
KMI, the exported-symbol genksyms **CRC shifts**, the vendor `.ko` is rejected at
load, and the phone bootloops.

**Configs that silently break KABI on this device — do NOT enable:**
- `CONFIG_CGROUP_DEVICE`, `CONFIG_CGROUP_PIDS` — grow `enum cgroup_subsys_id`,
  resize `struct css_set.subsys[]` (reachable from `task_struct`). Broke bootloop #1.
- `CONFIG_BRIDGE_NETFILTER`, `CONFIG_NF_TABLES` — shifted 113/115 exports in
  `kernel/sched/core.c`. Broke bootloop #2.
- `CONFIG_SYSVIPC` — only safe WITH the `ANDROID_KABI_RESERVE` relocation
  (`scripts/droidspaces/integrate.sh`): it moves `sysvsem`/`sysvshm` into reserve
  slots 6/7/8 so `task_struct` layout does not shift. Enabling SYSVIPC without that
  relocation = instant bootloop.

## Rule 2 — verify KABI BEFORE flashing (this is the test that saves you)

Hand-build genksyms and diff the CRCs against the boot-confirmed base:

```bash
make ARCH=arm64 LLVM=1 O=out gki_defconfig prepare scripts_genksyms
# for each file, run the exact clang -E -D__GENKSYMS__ | scripts/genksyms/genksyms -r /dev/null
# compare #SYMVER lines for these against the boot-tested base:
#   kernel/fork.c        (__put_task_struct)
#   kernel/sched/core.c  (wake_up_process, sched_setscheduler, set_cpus_allowed_ptr, runqueues, …)
```
If ANY exported-symbol CRC differs from the boot-tested base, a config broke KABI →
it WILL bootloop. `__ANDROID_KABI_CHECK_SIZE_ALIGN` is a compile-time assert, so
struct-slot arithmetic errors fail the build — but CRC shifts do NOT fail the build,
only the boot. genksyms diff is the only pre-flash check that catches them.

## Rule 3 — two mandatory post-merge fixes (or it won't compile/boot)

- `include/trace/events/timer.h`: keep the **2-arg** `hrtimer_start` tracepoint.
  Revert ACK's 3-arg `was_armed` version. The vendor `kernel/time/hrtimer.c`
  (offline-enqueue handling ACK reverted upstream, LineageOS keeps) calls it with
  2 args. 3-arg = `too few arguments` build error.
- `certs/extract-cert.c`: keep `key_pass` unconditional (this tree reaches it via
  `#elif defined(HAVE_OPENSSL_ENGINE)`, not `USE_PKCS11_ENGINE`).

## Rule 4 — keep the boot-safety reverts

The device base carries ~6,500 revert commits (qcom clock gating, qrtr spinlocks,
PM/suspend, dwc3, …). They undo upstream changes that break peridot hardware. They
are **why it boots**. Never strip them. Merge upstream (`git merge`), never
cherry-pick or fuzz-patch — cherry-picking loses the revert set; `--fuzz` force-fits
hunks into wrong functions.

## Rule 5 — updating the LTS or the device base

Merge, don't patch. `git merge` the ACK release tag (`android14-6.1.NNN_r00`) or
GuidixX `16.2` into `peridot-6.1.175`. Resolve conflicts **toward the device side**.
Do NOT apply mainline `patch-6.1.x` incrementals — mainline breaks the frozen KMI
(adds fields to `struct device`, widens `fwnode_handle.flags`, drops symbol
exports). See `docs/upgrading-gki-device-kernel-lts.md`.

## Rule 6 — root integration that actually boots

Use the proven pins + scripts (all in `peridot-6.1.175`), do not hand-integrate new
versions blind:
- KernelSU-Next: `v3.3.0` tag → `scripts/susfs/integrate.sh`
- SukiSU-Ultra: `susfs_new` @ `278d822a` → `scripts/susfs/integrate-sukisu.sh`
  (a different SukiSU version, e.g. v4.1.3, is UNPROVEN here — its supercall/susfs
  graft anchors differ; do not swap versions without re-verifying KABI + boot)
- ReSukiSU: `aa32736680c9` (native susfs)
- susfs4ksu: `8199bb65` (gki-android14-6.1, v2.2.0)

## Rule 7 — flash Image only

AnyKernel3 flashes `Image` only; stock `vendor_dlkm` is kept. Do NOT rebuild or
replace vendor modules — the whole KABI discipline above exists so the STOCK vendor
modules keep loading against our Image.

---
**TL;DR for a bootable build:** start from `peridot-6.1.175`, change nothing in the
KMI, keep the two post-merge fixes and the reverts, use the proven root pins/scripts,
genksyms-diff before flashing, flash Image only.
