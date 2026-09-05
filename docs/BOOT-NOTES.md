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
boot-tested, in the same commit, and say so. For a shift a device has already
booted through but whose flavor baselines are not all re-recorded yet (the ACK
176 `xfrm_*_km` case), list it with its new CRC and the boot evidence in
`scripts/ci/kmi-baseline/accepted-drift.txt` on that branch; the gate reports
it as `ACCEPTED` and keeps failing on everything else.

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
- susfs4ksu: `4fc9c189` (gki-android14-6.1, v2.3.0 — adds the zygote_next umount-inheritance
  mitigation, the open_redirect hook refactor and the sleepable-static_key WARN fix)

The integrate scripts accept exactly one patch reject — `fs/namespace.c`'s top-decl
hunk, which the fixup re-creates — and fail on any other. A new reject means the
base moved under the susfs patch; fix the port, do not delete the `.rej`.

## Rule 7 — flash Image only

AnyKernel3 flashes `Image` only; stock `vendor_dlkm` is kept. Do NOT rebuild or
replace vendor modules — the whole KABI discipline above exists so the STOCK vendor
modules keep loading against our Image.

**Why an Image with a different SUBLEVEL still loads them.** Every stock module
carries `vermagic=6.1.<their sublevel>-android14-11-g<sha> SMP preempt mod_unload
modversions aarch64`, which does not match ours. It loads anyway because
`CONFIG_MODVERSIONS=y` puts symbol CRCs in the module, and `same_magic()` in
`kernel/module/version.c` skips the leading version token when CRCs are present:

```c
/* First part is kernel version, which we ignore if module has crcs. */
if (has_crcs) { amagic += strcspn(amagic, " "); bmagic += strcspn(bmagic, " "); }
return strcmp(amagic, bmagic) == 0;
```

So the version string is *not* the contract; the exported-symbol CRCs are, which is
exactly what Rule 2's gate checks. Two things follow. The rest of the magic string
(`SMP preempt mod_unload modversions aarch64`) still has to match exactly, so
flipping `PREEMPT`/`SMP`/`MODVERSIONS` breaks every module load at once, with a
`version magic ... should be ...` error rather than an undefined-symbol one. And a
sublevel bump is free as long as no CRC moves — which is how `theettam-2.7-lts176`
(6.1.176) runs against a ROM whose modules were built at 6.1.175. Verified on
device: 444 modules loaded, zero `disagrees about version` lines.

The device-tree side of this contract (which tree builds the modules, and what not
to "tidy up" there) is written down in the ROM's device tree as
`docs/THEETTAM-KERNEL.md`.

---
## Rule 8 — upstream GuidixX `17` reverts (evaluated for 2.7)

On 2026-08-31 GuidixX's `17` branch reverted seven out-of-tree patches that 16.2 and
this tree carry, with no stated reason. Each was assessed against this tree:

| Patch | 2.7 decision | Why |
|---|---|---|
| `fork: fix double-free on task_struct` (`fcc2501b`) + `…of signal_struct` (`00883cb4`) | **reverted in 2.7** (GuidixX's `497b5dd9` + `cd40a6c5`, cherry-picked in that order) | The pair replaces `delayed_free_task()` with `put_task_struct()` on the copy_process() failure path, which runs the exit-time teardown on a child that still holds the parent's cred/signal/cgroup/dmabuf pointers: WARN on every failed clone, and unbalanced puts on the parent's creds, signal_struct, css_set and dmabuf accounting (a fatal signal racing pthread_create is enough). Two independent reviews confirmed; restores byte-identical ACK 6.1.175 code. Reverted together, as required. |
| `f2fs: Demote GC thread to idle scheduler class` | **reverted in 2.7** (GuidixX's `7e10766b`, cherry-picked) | With `GC_MERGE` on (kept, see below), foreground GC — where an app's write blocks in `TASK_UNINTERRUPTIBLE` until the GC kthread finishes — is executed by that same kthread; demoting it to `SCHED_IDLE` is a real priority inversion under CPU load, exactly when the fstab-mandated `GC_MERGE` needs it to run. The `IOPRIO_CLASS_IDLE` call from the same original patch stays (I/O-level deprioritization, no CPU-scheduling-class problem). |
| `f2fs: Enable ATGC and GC_MERGE by default` | keep | No KMI effect, every upstream follow-up fix is already in the tree, boot-tested v2.0–v2.6 — and moot on peridot: the ROM fstab already mounts /data with `atgc,gc_merge`. |
| `af_unix: GC cleanup and optimisation` | keep | Matches mainline 6.19 garbage.c; no exports touched; upstream never reverted it. |
| `sched: Make set_load_weight externally visible` | keep | Linkage-only no-op; nothing exported. |
| `mm/slab_common: Align all caches' objects to hardware cachelines` | keep | No KMI effect; ~10% more slab memory is the only known cost. |
| `drivers: arm-smmu: Stop panic` (new on 17, not a revert) | not adopted | `arm-smmu` is not built into our Image (vendor module from stock `vendor_dlkm`); adopting it changes nothing on device. |

None of these touch an exported symbol or a KMI struct; the decisions are about
correctness and behaviour, not boot safety, and every 2.7 build is still KMI-diffed
against the v2.6 baseline.

---
## Rule 9 — other correctness fixes taken in 2.7 (verified, not just proposed)

- **`kernel: sched: schedutil: Adjust frequency scaling ratio` reverted.** The
  patch discarded `next_freq` from the Android vendor governor hook
  (`trace_android_vh_map_util_freq`) and replaced it with an unconditional
  `freq = map_util_freq(...) * 3 / 4` — a flat 25% cut applied to *every*
  frequency decision, not "similar utilization" as claimed, and it fights
  BORE + uclamp's whole point of giving bursty UI work full frequency.
  Reverted to stock `get_next_freq()`. Local calculation only, no KMI impact.
- **Boeffla wakelock blocker's compiled-in default list emptied.**
  `LIST_WL_DEFAULT` (`drivers/base/power/boeffla_wl_blocker.h`) shipped with
  the real IPA/RMNET/`hal_bluetooth_lock` list despite the enabling commit's
  message claiming it was empty. `boeffla_wl_blocker_init()` bakes it into
  `list_wl_search` at boot regardless of `wl_blocker_active`; the moment
  anything (the Theettam Tweaks module's screen-off trip) flips the blocker on
  without first overwriting the list via sysfs, modem/data/bluetooth
  wakelocks get blocked — precisely the VoLTE/data risk this fork has hit
  before. Now genuinely empty.
- **`CONFIG_KFENCE_DEFERRABLE=y` added.** KFENCE's 500ms sampling timer was a
  non-deferrable `delayed_work`, forcing a CPU wake every cycle even at idle.
  Real upstream Kconfig option (`lib/Kconfig.kfence`), no KMI impact.
- **Dead ThinLTO linker flag removed** (`Makefile`, guarded by
  `CONFIG_LTO_CLANG_THIN` which this tree never sets — inert either way, but
  wrong on its own terms: `--thinlto-cache-dir` isn't a flag LLD's kernel
  link step understands and `$(nproc --all)` is evaluated at Makefile-parse
  time on whatever machine runs the build, not a real per-build tunable).
- **`set_load_weight()` now applies BORE's burst-score penalty** (previously
  deferred as needing more time; resolved). `nice()`/`sched_setattr()` call
  `set_load_weight()`, which only used `static_prio`, discarding
  `p->se.burst_score` — the exact penalty BORE computes for CPU hogs. The
  task's weight got reset to un-penalised on every priority-related syscall,
  and `update_burst_score()` only reweights when its own effective-priority
  computation *changes*, which it doesn't if `burst_score` hasn't ticked
  since — so a hog ran un-penalised for seconds after any such call, right
  when Android's constant `Process.setThreadPriority()` calls on fg/bg
  transitions matter most. Fix mirrors `fair.c`'s existing `effective_prio()`
  formula and clamp exactly (no new scheduler policy), gated on `update_load`
  so it only fires at the two syscall-driven call sites, not at fork time
  (`kernel/sched/core.c`, `kernel/sched/sched.h` for the `extern u8
  sched_bore;`). KMI-neutral (no export/struct change), built and KMI-gated
  on `plain` and `sukisu-susfs`. Needs an on-device UI-responsiveness check
  under sustained load in addition — this changes live scheduler weight
  behaviour, unlike the reverts above which restore known-safe prior states.
- **DroidSpaces/Premium: `NETFILTER_XT_MATCH_RECENT`,
  `NETFILTER_XT_TARGET_LOG`, `IP6_NF_NAT` added** to
  `scripts/droidspaces/droidspaces.config` (container flavors only — never
  touches the plain flavors' `gki_defconfig`). ufw's default rules and
  Docker ≥27's IPv6 bridge NAT need them. Given this exact file's history of
  two real bootloops from configs that looked equally KMI-unrelated by
  Kconfig inspection alone, this was validated with a real
  `ksun-susfs-droidspaces` build + KMI gate before landing, not just static
  analysis: `changed=0 removed=0`.
- **`scripts/device/device-probe.sh` added** — read-only sysfs/proc dump
  (I/O scheduler, cpuidle governor, MTE/KASAN exposure, DAMON/LRU-sort
  runtime state, f2fs/zram settings) for the on-device data several items
  below still need. Safe to run any time; writes nothing.

**Considered and explicitly rejected** (verified against real ACK/GuidixX
history, not implemented): disabling `IKHEADERS`, `HEADERS_INSTALL`,
`PID_IN_CONTEXTIDR`, or UBSAN — all match Google's own ACK android14-6.1.175
`gki_defconfig` value; deviating for a build-time-only or negligible-runtime
saving breaks this tree's "match ACK's own considered defaults" philosophy
for no real benefit. `CONFIG_PM_WAKELOCKS_LIMIT=10` (ACK ships `0`) was
**not** touched: it is already the value on `guidixx/16.2` itself, i.e. part
of the device base, not a Theettam deviation — changing it needs a reason
beyond "differs from generic ACK". `-O3`, `-mcpu=`, and Polly are rejected
for release Images (ThinLTO is a separate, symvers-gated experiment only,
never for releases): compiler-flag changes never move a genksyms CRC (hash of
preprocessed source, not codegen) so the KMI gate cannot validate them at all
— any such experiment needs its own boot test.

**KMI-locked, do not retry disabling:** `CONFIG_PAGE_OWNER` /
`CONFIG_PAGE_PINNER` (→ `CONFIG_PAGE_EXTENSION`). This was tried twice before
(`ce1467042a5f` disabled it for battery, `1895162f6183` re-enabled it as a
"suspected" boot breaker) without ever confirming why. It is a real KMI break:
`mm/page_owner.c` exports `page_owner_inited` etc., and `PAGE_EXTENSION` adds
a field to `struct mem_section`, whose CRC vendor modules can depend on. Leave
it on; it is a compile-time-only cost unless `page_owner=on` is set on the
cmdline (it is not).

**Answered on device (2026-09-03, `scripts/device/device-probe.sh` on the
lts176 plain flavor, unprivileged reads):**
- `cpuidle` governor live is the vendor's **`qcom-cpu-lpm`** (`available_governors:
  menu teo qcom-cpu-lpm`, LPM module loaded). The Image's `menu`/`teo` choice is
  moot on peridot; do not spend effort there.
- `HZ=300` is what runs (`/proc/config.gz`: `CONFIG_HZ_300=y`, `NO_HZ_IDLE`), and
  the full stock `vendor_dlkm` set (445 modules) loads against it. The
  "vendor modules expect HZ=250" worry is retired.
- MTE is **off at boot**: stock cmdline carries `kasan=off`
  (`kasan.page_alloc.sample=10 kasan.stacktrace=off` too) and `mte` is absent
  from `/proc/cpuinfo`. `CONFIG_KASAN_HW_TAGS=y` stays only because GKI/KMI
  wants it compiled in; it costs nothing at runtime here.
- cpufreq governor is vendor `walt` on all three policies (cmdline's
  `cpufreq.default_governor=performance` is overridden by init); MGLRU is on
  (`lru_gen/enabled: 0x0003`); THP is `[never]`; `/data` is f2fs with
  `atgc,age_extent_cache,fsync_mode=nobarrier,lookup_mode=perf`.
- Root-gated values, read the same day on the rooted (SukiSU-Ultra + SUSFS)
  lts176 flavor: **ADIOS 3.2.0 is the live scheduler** on every UFS LU
  (`mq-deadline kyber [adios] bfq none`, `nr_requests` 126, `read_ahead_kb`
  512); zram 6 GiB `lz4`, `swappiness` 70, `watermark_scale_factor` 44; MGLRU
  on, `min_ttl_ms` 0; **DAMON reclaim/LRU-sort both `N`** (so the unported
  DAMON restart fix in Rule 10 really is dormant); `watchdog_thresh` 10,
  `soft_watchdog` 1, `sync_on_suspend` 1; `kptr_restrict` 2,
  `dmesg_restrict` 0 (SELinux still blocks the shell's klogctl),
  `bpf_jit_harden` 0, **`unprivileged_bpf_disabled` 0** (Rule 11).
- ROM-side, not kernel: this ROM boots with `perf_event_paranoid=-1` and
  `fs.protected_symlinks`/`protected_hardlinks`=0. Those are init sysctls, so
  they belong in the Theettam Tweaks userspace module as reversible defaults
  (3 / 1 / 1), not in a kernel config.

**Deferred, out of scope for the kernel tree:** on-device idle/battery A/B
tests (I/O scheduler choice, softlockup watchdog period, `sync_on_suspend`)
belong in the Theettam Tweaks userspace module as runtime sysctls, not a
kernel default — they are reversible without a new flash there.

## Rule 10 — ACK android14-6.1.176 bump (promoted to theettam-2.7 on 2026-09-04)

`android14-6.1.176_r00`, 639 commits ahead of our 175 base
(`git rev-list --count android14-6.1.175_r00..android14-6.1.176_r00`), has
been merged and hand-resolved on a separate branch. **Not promoted to
`theettam-2.7`** — it needs a device boot test first; everything short of
that has been done. `SUBLEVEL` is now 176; `scripts/ci/build-flavor.sh`'s
base check accepts both 175 and 176.

3 conflicting files, 503+ auto-merged cleanly, each hand-resolved by finding
the *provenance* of our side (not by picking whichever side looked simpler —
see below) and rebuilt + KMI-gated afterward (`plain`: `changed=0 removed=0`
except the xfrm note below; the merge touches nothing SUSFS/DroidSpaces
grafts onto, so those flavors weren't independently re-validated against 176):

- `drivers/slimbus/qcom-ngd-ctrl.c` — two hunks, both pure additions on our
  side (`trace_rproc_qcom_event` logging + `qcom_slim_ngd_down()` PDR
  cleanup) that 176 simply doesn't have. Kept both.
- `net/qrtr/af_qrtr.c` — the `qrtr_port_lock` spinlock (used consistently at
  4 sites in the file) vs. 176's `xa_erase()` + `synchronize_rcu()` at this
  one site only. Taking 176's side here would leave 3 sites on the spinlock
  and 1 on RCU — an inconsistent locking model. Kept our spinlock.
- `net/qrtr/ns.c` — 4 hunks, none of them the kthread-vs-workqueue difference
  they looked like at a glance (stock ACK 175 *itself* already uses a plain
  `workqueue_struct`; our RT `kthread_worker` is a real Qualcomm commit,
  `a729cfdb0bb4`, layered on top — "if worker is not processing packets on
  control port fast enough, socket buffer may get full and result in drop of
  control packets"). Reconciled by finding each side's actual origin
  (`git log -S<anchor text>`) rather than guessing from the diff shape:
  - struct decl: combined 176's new `u32 lookup_count` (a real DoS-prevention
    fix, `6e3675251fce`) with our kthread fields — both needed, no overlap.
  - `announce_servers()`: kept our all-nodes iteration
    (`81f44092bc11`, Qualcomm, "ns service was notifying only local node ID
    services after a pci disconnect and reconnect" — a real bug fix 176
    doesn't have, since ACK's qrtr has no multi-node PCIe transport case).
  - `ctrl_cmd_bye()`: **took 176's side** — it adds a `delete_node:` label +
    `xa_erase`+`kfree` (`25d580a46b07`, a real memory-leak fix: the node was
    never freed on client disconnect). Confirmed forced, not optional: part
    of 176's change (a `goto delete_node` guard) auto-merged cleanly just
    above this hunk, so keeping our side would leave a dangling `goto` with
    no matching label — a compile error, not just a missed fix.
  - `ctrl_cmd_del_client()`: kept our side — ratelimited logging that
    continues the broadcast loop on a single send failure instead of
    aborting it (`718816b95232`, Qualcomm, "prevent performance issues when
    a client socket is full" — again a real fix 176 lacks).
- **KMI note**: `plain` shows 3 CHANGED symbols — `km_migrate`,
  `xfrm_register_km`, `xfrm_unregister_km` (176 added a `struct net *`
  parameter to route XFRM MIGRATE notifications to the correct netns,
  `fe4637983433` — a real upstream fix, security-relevant for
  namespace-isolated setups like DroidSpaces). None of the three are in
  `android/abi_gki_protected_exports_*` or `abi_gki_aarch64*` — GKI does not
  guarantee their stability across LTS bumps — and their only in-tree
  referencers are `net/xfrm/xfrm_state.c`, `net/xfrm/xfrm_user.c`,
  `net/key/af_key.c`, all built directly into the Image (`CONFIG_XFRM=y`,
  `CONFIG_NET_KEY=y`), not a loadable vendor module. No plausible phone
  vendor driver (wifi/bt/display/touch/camera/modem) references IPsec
  key-manager registration. Judged safe by this reasoning, **not** by an
  actual boot — that judgment call is exactly why this stays off
  `theettam-2.7` until a device confirms it.
- **Boot record, 2026-09-03 — the plain (no-root) lts176 flavor boots on a
  peridot (24069PC21I, HyperOS-based ROM `peridot:24.0-20260829-UNOFFICIAL`).**
  Verified without root over `adb`: `uname -r` =
  `6.1.176-android14-11-ga3b9c44908dd-ab13320413`, 445 vendor modules loaded
  (same count as the 175 baseline), display/touch/wifi/bt/audio/GPU up, RIL
  alive (modem scans cells, so the qrtr/ipc merge resolution works at least
  that far), 42+ min uptime with load ~1.3 and no visible misbehaviour.
  **Not verified yet**: `dmesg` (klogctl is root-only on Android, so "no
  oops/`disagrees about version`" is unconfirmed — the plain flavor has no
  `su`), and VoLTE/IMS, which could not be tested at the time because no SIM
  was inserted (`gsm.sim.state=[ABSENT,ABSENT]`; the OUT_OF_SERVICE state was
  that, not a kernel fault). Both were closed out later — see the rooted boot
  record and the telephony entry below.
- **Boot record, 2026-09-03 (later) — the SukiSU-Ultra + SUSFS lts176
  flavor boots and roots on the same peridot.** Flashed with OrangeFox
  sideload, then the SukiSU manager (v4.2.0) shows Working / driver 40901-2
  / SuSFS v2.3.0 (Tracepoint Syscall Redirect) / SELinux Enforcing, and
  `su` from adb gives `uid=0 context=u:r:ksu:s0` once Shell is granted.
  `scripts/device/postflash-check.sh` rooted: **PASS=11 FAIL=0**, 444 vendor
  modules, `/proc/config.gz` scrubbed, SUSFS initialised (29 dmesg lines).
  `dmesg` (21.5k lines): **no `disagrees about version`, no module load
  failure, no panic/BUG/lockup/Oops**, i.e. the accepted xfrm CRC drift is
  benign in practice for the whole stock `vendor_dlkm`. Exactly two
  `WARNING: CPU:` sites, both inside stock vendor modules and expected on
  every boot: `drivers/spmi/spmi-pmic-arb.c:309` (`qcom_spmi_pmic` probing a
  PMIC address that answers "transaction failed" at 0.26 s) and
  `kernel/irq/manage.c:914` (`goodix_ts` gesture resume doing an unbalanced
  IRQ 321 wake disable). postflash-check lists both as known.
- **Telephony verified, 2026-09-04 — the last gate on the 176 promotion is
  closed.** With a Jio SIM inserted (`gsm.sim.state=LOADED`, operator
  "Jio True5G"), `dumpsys telephony.registry` reports
  `mVoiceRegState=0(IN_SERVICE)` and `mDataRegState=0(IN_SERVICE)`, and the
  whole IMS stack is up: `imsdaemon`, `org.codeaurora.ims`,
  `ims-dataservice-daemon`, `ims_rtp_daemon`. A call to 198 (the carrier's
  toll-free service line) reached `telecom=ACTIVE` / `mCallState=2` and held
  it, and the maintainer confirmed hearing the IVR — so audio really flowed,
  not just session setup.
  Worth recording precisely what path it took: idle, the phone sat on
  `IWLAN` (Wi-Fi calling) because `mobile_data=0`, but at call setup
  `gsm.network.type` switched to **`NR_SA`** and stayed there for the whole
  call. On this carrier that is VoNR over 5G standalone rather than VoLTE
  over LTE — either way it is the real cellular IMS path through the modem,
  which is the thing the ACK 176 merge could have broken. This is the check
  Rule 0 exists for: `DEBUG_INFO_BTF=n` once broke calls on this fork while
  registration still looked perfectly healthy, so registration state alone
  was never going to settle it.
- The SukiSU manager shows a red "Manager version (40900) and KernelSU
  driver version (40901) mismatch" banner with our `susfs_new` pin: the
  driver number is `git rev-list --count` of the branch we build from, the
  manager's is that of the release tag on `main`, and they differ by one.
  Everything works; it is cosmetic until SukiSU publishes a manager built
  past our pin. Do not "fix" it by bumping the pin without a boot test.
- **Considered and not ported**: upstream's DAMON_RECLAIM/DAMON_LRU_SORT
  "fresh status" fix (`2f54908fae21`/`2f32fb0e0c32` — a kdamond that stops
  itself on bad input or an allocation failure can't be restarted before
  reboot). Both commits are technically ancestors of `android14-6.1.176_r00`,
  but their actual change to `mm/damon/reclaim.c`/`lru_sort.c` isn't present
  at the 176 tag's tip — some later ACK merge kept ACK's own version instead
  — and the fix calls `damon_is_running()`, which doesn't exist anywhere in
  our tree *or* in ACK 176 itself. Porting it needs chasing down that missing
  helper too, not just two file diffs as it first looked. Low urgency:
  `DAMON_RECLAIM`/`DAMON_LRU_SORT` are disabled at runtime by default
  (`/sys/module/damon_reclaim/parameters/enabled` — verify with
  `scripts/device/device-probe.sh`), so the bug has zero effect unless
  something (the Theettam Tweaks module) explicitly enables them.

## Rule 11 — security review against ACK past 176 (2026-09-03): what was taken, what was refused, and why

Scoped to code that is actually **linked into the Image** (`=y`). Anything that
lives in a stock `vendor_dlkm`/`system_dlkm` module is Xiaomi's to fix via OTA;
an Image-only flash (Rule 7) cannot deliver it, however loud the bulletin.

- **Taken: `39905027d023` "ANDROID: netfilter: xt_quota2: fix UAF in
  q2_get_counter error path"** (Todd Kjos, ACK android14-6.1-lts just past
  176, Bug 499166786). `xt_quota2` is Android's own per-UID accounting match
  and is `=y` here, so it is in the Image. The bug: the new counter is put on
  `counter_list` and the lock dropped before `proc_create_data()`; if that
  fails, the old error path did `list_del()`+`kfree()` unconditionally while
  another thread could already hold a reference. Needs CAP_NET_ADMIN and a
  procfs allocation failure, so not an app-level bug, but the fix is three
  lines of refcount discipline with no struct or export change (KMI gate:
  `changed=0`). On both `theettam-2.7` and `theettam-2.7-lts176`.
- **Refused: the fscrypt trio** `c3e0109ec5e6` (avoid dynamic allocation in
  `fscrypt_get_devices`), `2fd20b5fee78` (replace `mk_users` keyring with a
  list), `f20ce2195cc1` (key setup with multiple data unit sizes). fscrypt is
  very much in this Image (`FS_ENCRYPTION`, inline crypt) and the third one
  reads like a correctness fix worth having. It is a trap: ACK could only land
  them by filing a declared ABI break (`c0df533a5806` adds them to
  `abi_gki_aarch64.stg.allowed_breaks`: `struct fscrypt_master_key` shrinks
  from 872 to 368 bytes, and `struct fscrypt_operations` gains
  `get_devices_new` by **consuming `android_kabi_reserved1`**). That struct is
  embedded in every encrypting filesystem's superblock ops; Google absorbs it
  by rebuilding the whole device image, we flash Image only. Never for this
  fork, unless a full LTS bump Google has shipped to peridot carries it.
- **Kept against ACK's revert: `47455f9704a1` "usb: gadget: udc: fix UAF in
  usb_gadget_state_work (KABI-safe)"**, which 176 carries and ACK later
  reverted as `e70cf19d88cf`. The revert's own reason is "presubmit failures
  when backported to 6.12", to be replaced by an internal teardown flag in
  `struct usb_udc`: a 6.12 build problem plus a refactor plan, not a 6.1
  runtime regression, and both versions are explicitly KABI-safe. The path is
  hot on peridot (`usb_gadget_set_state`/`usb_udc_vbus_handler` are exports
  the dwc3 vendor module hits on every cable event) and the 176 build with it
  booted. Do not "sync" this revert; re-evaluate when ACK lands the flag.
- **ASB-2026-08-03_14-6.1: nothing for us.** It is nine commits past 176;
  seven are vendor hooks/symbol lists/a kernel-doc fix. The two real fixes,
  `cad04476381e` + `b178698e5ac5` (Bluetooth SCO sleeping-under-spinlock and
  `sco_conn_ready` UAF), are `net/bluetooth/sco.c` only, and `CONFIG_BT=m`:
  that code is `bluetooth.ko` in stock `system_dlkm`. Cherry-picking them
  changes nothing on the phone; the device gets them from Xiaomi's OTA.
- **Qualcomm bulletins (Jun–Sep 2026): no actionable item, structurally.**
  The complete Qualcomm-authored code in this Image is `ARCH_QCOM` plumbing
  plus `PCIE_QCOM`, `INTERCONNECT_QCOM`, `QCOM_GDSC`, `QCOM_GENI_SE`,
  `SERIAL_QCOM_GENI`, `QCOM_SMEM_STATE`, `QCOM_EBI2`, SPMI regmap,
  `USB_DWC3_QCOM`, the SCMI transports and the Gunyah core; there is not one
  `CONFIG_*QCOM*=m`/`*MSM*=m`. KGSL, camera, display, audio, WLAN, IPA/rmnet,
  video, qseecom, fastrpc are all vendor modules, which is where Qualcomm's
  kernel CVEs overwhelmingly land (e.g. CVE-2026-21385, KGSL, "limited,
  targeted exploitation": `msm_kgsl.ko`, untouchable from here). Even `QRTR`
  and `SLIMBUS` are not set, so the hand-resolved 176 merge conflicts in
  `net/qrtr` and `drivers/slimbus` (Rule 10) affect no shipped code. The
  per-CVE bulletin tables could not be read (client-side rendered); the
  attack-surface list above is the verifiable statement.
- **Hardening audit vs ACK 176 `gki_defconfig`: parity, nothing to flip.**
  The full defconfig delta is 97 lines and the only security-relevant ones are
  `MODULE_SIG`/`MODULE_SIG_PROTECT` off (the deliberate KernelSU accommodation:
  anything with CAP_SYS_MODULE can insmod, inherent to a root kernel) and our
  `KFENCE_DEFERRABLE=y`. Present and identical to ACK: `CFI_CLANG` (permissive
  off), `SHADOW_CALL_STACK`, `KASAN_HW_TAGS`, `INIT_ON_ALLOC_DEFAULT_ON`,
  `INIT_STACK_ALL_ZERO`, `HARDENED_USERCOPY`, `SLAB_FREELIST_RANDOM`/`HARDENED`,
  `STACKPROTECTOR_STRONG`, `RANDOMIZE_BASE`, `FORTIFY_SOURCE`, `UBSAN_BOUNDS`
  (+trap), `BUG_ON_DATA_CORRUPTION`, `DEBUG_LIST`, `STRICT_KERNEL_RWX`/
  `MODULE_RWX`, `VMAP_STACK`, PAN/E0PD/EPAN/`UNMAP_KERNEL_AT_EL0`, pointer
  auth, `STATIC_USERMODEHELPER`, `DEVMEM`/`PROC_KCORE` off, `SECCOMP_FILTER`.
  Checked and deliberately not proposed: `INIT_ON_FREE_DEFAULT_ON` (off in
  ACK too, real runtime cost) and `SECURITY_DMESG_RESTRICT` (off in ACK,
  Android sets the sysctl anyway).
- **Closed, no-op on Android: `BPF_UNPRIV_DEFAULT_OFF`.** The rooted probe
  read `unprivileged_bpf_disabled=0` and dmesg carries "WARNING: Unprivileged
  eBPF is enabled, data leaks possible via Spectre v2 BHB attacks!" at 6.6 s.
  Flipping the config and booting it changed nothing: the value still read 0
  and the notice still printed, because the notice is emitted on the
  *sysctl write* and the write comes from Android itself: it lands right
  after `NetBpfLoad` (`/apex/com.android.tethering/bin/netbpfload`, uid 0,
  whose binary contains the `/proc/sys/kernel/unprivileged_bpf_disabled`
  path) on every boot. The config's default is 2, which root may lower; only
  1 is the one-way latch, and forcing 1 would fight the platform's BPF
  loader. Leave it unset, as ACK does. Recorded so nobody flips it again on
  the strength of the dmesg line.
- **Expected BTF noise on every boot: ~250 `BPF: [<id>] Invalid
  name_offset:<n>` lines at 0.16 s and "Kernel module BTF mismatch detected,
  BTF debug info may be unavailable for some modules".** That is the stock
  `vendor_dlkm` modules' split BTF (generated against Xiaomi's vmlinux)
  failing to attach to ours; `/sys/kernel/btf/vmlinux` itself loads (5.7 MB)
  and module BTF only matters for tracing on module types. Inherent to
  Image-only flashing with stock modules, not a regression, and unrelated to
  the `DEBUG_INFO_BTF=n` breakage in Rule 0 (that removed vmlinux BTF).

## Rule 12 — who actually owns the clocks on this device (measured 2026-09-04)

Both big CPU clusters and the GPU run below their hardware maximum, always, and
none of it is the kernel's doing. Written down because two people have now
assumed the kernel could tune it.

**The GPU.** `cooling_device37` (type `gpu`) is bound to no thermal zone at all —
every GPU zone binding resolves to `cooling_device36`, the kernel's own devfreq
cooling device, which sits at state 0. `cooling_device37` is driven purely by
`/vendor/bin/mi_thermald`, from `[INDIA-MONITOR-GPU]` in the decrypted regional
map: one trip at **15 °C** against a composite sensor that reads 33–36 °C, so it
is tripped permanently and asks for cooling state 3 forever.

Here the kernel does help. `drivers/thermal/qcom/qti_devfreq_cdev.c` carries
commit `80accb269363`, which remaps mid-range cooling states (start 1, divider 2,
critical tail 2) and turns that requested state 3 into a stored 2 — 950 MHz
instead of 900. **Measured on device**, driving `cur_state` with the power-HAL
ceiling lifted:

```
written 0 -> stored 0 -> max_freq 1100000000     written 4 -> stored 3 -> 900000000
written 1 -> stored 1 ->         1000000000      written 3 -> stored 2 -> 950000000
written 2 -> stored 2 ->          950000000
```

Writing 4 storing 3, and 3 storing 2, is the remap running. At state 0 the GPU
reaches the full 1100 MHz, so the hardware and the OPP table are fine; only the
cooling request holds it down.

**The CPU — and this is the part that surprises.** The caps are real:

```
policy0 (silver) scaling_max 2016000 == cpuinfo_max      no cap
policy3 (gold)   scaling_max 2572800 vs 2707200 available   top 2 OPPs unreachable
policy7 (prime)  scaling_max 2668800 vs 2918400 available   top 2 OPPs unreachable
```

and they come from the same daemon, via step curves whose **first step trips at
25 °C** — a temperature a phone in use is never below:

```
[INDIA-SS-CPU3] trig 25000 37000 39000 ...  target 2572800 2188800 1920000 ...
[INDIA-SS-CPU7] trig 25000 37000 39000 ...  target 2668800 2304000 2150400 ...
```

The composite sensor read 32969 when measured, i.e. past step 0 and below step 1,
so the applied ceilings are exactly `2572800` and `2668800` — precisely what the
sysfs files read.

**But the CPU half of `80accb269363` does nothing on this device.** Those targets
are frequencies in kHz, not cooling states: `strings /vendor/bin/mi_thermald`
contains `/sys/devices/system/cpu/cpu%d/cpufreq/scaling_max_freq`, and the daemon
writes the ceiling directly. The three cooling devices that `qti_cpufreq_cdev.c`
registers and that the commit remaps — `cpufreq-cpu0`, `cpufreq-cpu3`,
`cpufreq-cpu7` — all read `cur_state=0`, unused. No CPU cooling device is bound
to a thermal zone either. So the CPU remap is inert here; keep it (it is correct,
and it would apply on a ROM that drives the cooling devices) but do not expect it
to buy anything on this one.

**Consequence for tuning.** The CPU ceilings are not reachable from the kernel or
from the device tree: `mi_thermald`, `thermald-devices.conf` and the regional map
are extracted vendor blobs, the map is encrypted, and the daemon re-asserts every
2000 ms, so a userspace module cannot hold a higher value either. Changing them
means replacing the thermal policy wholesale, which is a real thermal decision
wanting sustained-load measurement — not a tweak. Do not "fix" this by raising
`scaling_max_freq` somewhere and calling it a win; it will be overwritten within
two seconds.

---
**TL;DR for a bootable build:** start from `theettam-2.7`, change nothing in the
KMI, keep the two post-merge fixes and the reverts, use the pins in
`scripts/ci/pins.env` via `scripts/ci/build-flavor.sh`, let the symvers gate run
before flashing, flash Image only.
