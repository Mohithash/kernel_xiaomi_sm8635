# Making this kernel BOOT — hard-won notes (read before touching the tree)

Every rule here comes from a build that compiled cleanly and then **bootlooped**.
On GKI, **a clean compile proves almost nothing about booting.** The bar is: does
the kernel load the device's prebuilt vendor modules? If not → bootloop.

## Rule 0 — build ON the boot-confirmed tree, do not rebuild from scratch

The boot-confirmed lineage is tag **`v2.6`** (commit `4f00f1dc16f6`: SUBLEVEL **175**,
GKI `android14-6.1.175` + GuidixX 16.2 + our delta), continued on branch
**`theettam-2.7`**. It **already builds** all seven flavors, and v2.6 was boot-tested
on every one of them:

- KernelSU-Next v3.3.0, plain and + SUSFS v2.2.0
- **SukiSU-Ultra + SUSFS v2.2.0**
- ReSukiSU + SUSFS v2.2.0 (native)
- **KSUN + SUSFS + DroidSpaces** (LXC containers), and **Premium** (SukiSU + SUSFS + DroidSpaces)
- APatch / KernelPatch (Image patched post-build)

> **The branch literally named `peridot-6.1.175` on origin is NOT this tree.** On
> 2026-08-11 it was force-pushed with a squashed "source snapshot": nine commits, no
> merge-base with anything, no `.github/workflows`, no `vmlinux.lds.S`, a foreign
> `include/asm-generic/vmlinux.lds.h`, `DEBUG_INFO_BTF=n` (breaks VoLTE), and
> committed `.bak`/`.orig` files. Never branch from it, merge into it, or run its
> config. The real history lives at tag `v2.6` and on `theettam-2.7`.

Branching from an OLD base (e.g. `209fbd25`, SUBLEVEL 173) and hand-re-integrating
SukiSU/SUSFS/network patches is how you get a non-booting kernel. It throws away
the 175 LTS, the July security/vendor fixes, and every proven integration. **Start
from `theettam-2.7`.**

Build with `scripts/ci/build-flavor.sh <flavor>` in a git worktree — it is the same
script `.github/workflows/build-theettam.yml` runs, with the pins from
`scripts/ci/pins.env`. A local build and a CI build are the same steps.

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

`CONFIG_MODVERSIONS=y` already writes every exported symbol's genksyms CRC into
`out/Module.symvers`, so the check is a diff:

```bash
# baseline = the boot-tested build of the same flavor (scripts/ci/kmi-baseline/<flavor>.symvers,
# recorded from the v2.6 builds); candidate = what you just built
scripts/ci/symvers-diff.sh scripts/ci/kmi-baseline/sukisu-susfs.symvers out/Module.symvers
```
`build-flavor.sh` runs this automatically after every build and **fails** on any
CHANGED or REMOVED CRC (CI sets `KMI_STRICT=1` so a missing baseline also fails).
Symbols that only get ADDED are fine. If ANY exported-symbol CRC differs from the
boot-tested base, a config broke KABI → it WILL bootloop. `__ANDROID_KABI_CHECK_SIZE_ALIGN`
is a compile-time assert, so struct-slot arithmetic errors fail the build — but CRC
shifts do NOT fail the build, only the boot. The symvers diff is the only pre-flash
check that catches them. The symbols that shifted in the two documented bootloops were
`__put_task_struct` (kernel/fork.c) and 113 of the 115 exports in kernel/sched/core.c
(`wake_up_process`, `sched_setscheduler`, `set_cpus_allowed_ptr`, `runqueues`, …).

When a change is *meant* to move a CRC (it never is, for an Image-only kernel that
keeps stock `vendor_dlkm`), regenerate the baseline from a build that has been
boot-tested, in the same commit, and say so.

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
GuidixX `16.2` into `theettam-2.7`. Resolve conflicts **toward the device side**
(the 2.7 merge of GuidixX 16.2 @ `48d7bba4` conflicted only on `CONFIG_LOCALVERSION`
and the legacy `build.sh` version string; ours won both).
Do NOT apply mainline `patch-6.1.x` incrementals — mainline breaks the frozen KMI
(adds fields to `struct device`, widens `fwnode_handle.flags`, drops symbol
exports). See `docs/upgrading-gki-device-kernel-lts.md`.

## Rule 6 — root integration that actually boots

Use the proven pins + scripts, do not hand-integrate new versions blind. The pins
live in **`scripts/ci/pins.env`** (full 40-char SHAs — short SHAs cannot be fetched
after a shallow clone and silently fall back to branch tip, which is exactly how the
premium CALLSAFE CI drifted to the wrong susfs and failed its KABI gate):
- KernelSU-Next: `v3.3.0` tag → `scripts/susfs/integrate.sh`
- SukiSU-Ultra: `susfs_new` @ `278d822a` **plus** three kernel-side commits
  cherry-picked from `main` (`baf01faf3e`, `e15a797322`, `6428b35f84`; see
  `SUKISU_MAIN_CHERRYPICKS`) → `scripts/susfs/integrate-sukisu.sh`
  (a different SukiSU version, e.g. v4.1.3, is UNPROVEN here — its supercall/susfs
  graft anchors differ; do not swap versions without re-verifying KABI + boot)
- ReSukiSU: `0b4f56fd` (native susfs) → `scripts/susfs/integrate-native.sh`
- susfs4ksu: `090cf407` (gki-android14-6.1, v2.2.0 + Jul 23 OPEN_REDIRECT fixes)

The integrate scripts accept exactly one patch reject — `fs/namespace.c`'s top-decl
hunk, which the fixup re-creates — and fail on any other. A new reject means the
base moved under the susfs patch; fix the port, do not delete the `.rej`.

## Rule 7 — flash Image only

AnyKernel3 flashes `Image` only; stock `vendor_dlkm` is kept. Do NOT rebuild or
replace vendor modules — the whole KABI discipline above exists so the STOCK vendor
modules keep loading against our Image.

---
## Rule 8 — upstream GuidixX `17` reverts (evaluated for 2.7)

On 2026-08-31 GuidixX's `17` branch reverted seven out-of-tree patches that 16.2 and
this tree carry, with no stated reason. Each was assessed against this tree:

| Patch | 2.7 decision | Why |
|---|---|---|
| `fork: fix double-free on task_struct` (`fcc2501b`) + `…of signal_struct` (`00883cb4`) | **reverted in 2.7** (GuidixX's `497b5dd9` + `cd40a6c5`, cherry-picked in that order) | The pair replaces `delayed_free_task()` with `put_task_struct()` on the copy_process() failure path, which runs the exit-time teardown on a child that still holds the parent's cred/signal/cgroup/dmabuf pointers: WARN on every failed clone, and unbalanced puts on the parent's creds, signal_struct, css_set and dmabuf accounting (a fatal signal racing pthread_create is enough). Two independent reviews confirmed; restores byte-identical ACK 6.1.175 code. Reverted together, as required. |
| `f2fs: Demote GC thread to idle scheduler class` | keep (needs device data) | Boot-safe either way; with `GC_MERGE` on, foreground GC waits on this thread, so SCHED_IDLE can stall writers under CPU load — but no field evidence yet. Decide with the ATGC/GC_MERGE item. |
| `f2fs: Enable ATGC and GC_MERGE by default` | keep | No KMI effect, every upstream follow-up fix is already in the tree, boot-tested v2.0–v2.6 — and moot on peridot: the ROM fstab already mounts /data with `atgc,gc_merge`. |
| `af_unix: GC cleanup and optimisation` | keep | Matches mainline 6.19 garbage.c; no exports touched; upstream never reverted it. |
| `sched: Make set_load_weight externally visible` | keep | Linkage-only no-op; nothing exported. |
| `mm/slab_common: Align all caches' objects to hardware cachelines` | keep | No KMI effect; ~10% more slab memory is the only known cost. |
| `drivers: arm-smmu: Stop panic` (new on 17, not a revert) | not adopted | `arm-smmu` is not built into our Image (vendor module from stock `vendor_dlkm`); adopting it changes nothing on device. |

None of these touch an exported symbol or a KMI struct; the decisions are about
correctness and behaviour, not boot safety, and every 2.7 build is still KMI-diffed
against the v2.6 baseline.

---
**TL;DR for a bootable build:** start from `theettam-2.7`, change nothing in the
KMI, keep the two post-merge fixes and the reverts, use the pins in
`scripts/ci/pins.env` via `scripts/ci/build-flavor.sh`, let the symvers gate run
before flashing, flash Image only.
