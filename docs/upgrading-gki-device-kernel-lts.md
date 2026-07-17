# Upgrading an Android GKI device kernel to a newer LTS

### Why your kernel is stuck at 6.1.173, and how to merge ACK `android14-6.1-lts` to move it

<sub>Written from bumping the Xiaomi peridot (POCO F6 / Redmi Turbo 3, SM8635) from **6.1.173 to 6.1.175**.
Every command, error and number below is from that bump. The method is device-agnostic — it applies to any
GKI `android14-6.1` device kernel.</sub>

---

## The problem

Your device kernel says `SUBLEVEL = 173`. Upstream is well past it. You want the LTS fixes. So you do the
obvious thing:

```bash
wget https://cdn.kernel.org/pub/linux/kernel/v6.x/patch-6.1.174.xz
xzcat patch-6.1.174.xz | patch -p1
```

**This does not work, and the reason is the single most important thing to understand about GKI.**

---

## Mainline ≠ ACK

There are two different 6.1.175 kernels:

| | Source | Purpose |
|:--|:--|:--|
| **Mainline LTS** | `kernel.org` `linux-6.1.y` | The upstream stable tree |
| **ACK** | `android.googlesource.com/kernel/common`, branch `android14-6.1-lts` | Android Common Kernel — mainline LTS **adapted to preserve the frozen KMI** |

Android GKI freezes the **KMI** (Kernel Module Interface) for the life of a branch. Vendor modules —
your device's UFS, display, camera, touch drivers — are **prebuilt binaries** linked against that
interface. Change a struct layout, and they break.

Mainline LTS does not care about your KMI. Concretely, mainline 6.1.175 does all of this:

- adds a bitmap field to `struct device`
- widens `fwnode_handle.flags` from `u8` to `unsigned long`
- drops `EXPORT_SYMBOL_GPL(ufshcd_dealloc_host)`

Each of those is a KABI break. Apply them and you get a kernel that compiles and then fails to load the
vendor modules that make your phone a phone.

**ACK's entire job is to take each mainline LTS and re-land it without breaking the KMI**, using
`ANDROID_KABI_RESERVE` slots so struct sizes never move:

```c
/* ACK adds a field without changing the struct's layout: */
ANDROID_KABI_USE(1, unsigned long new_field);
```
`__GENKSYMS__` makes genksyms see the original layout, so the symbol CRCs are unchanged and prebuilt
modules still load.

> **The rule:** never apply mainline incrementals to a GKI device kernel. Merge ACK's release tag instead.

---

## Why "just skip the rejects" fails

The tempting shortcut is to apply the mainline patch and drop whatever conflicts. Here is what that
actually produces:

```
fs/f2fs/node.c:2789:38: error: use of undeclared identifier 'STOP_CP_REASON_CORRUPTED_NID'
```

The **definition** was in `f2fs_fs.h`, which rejected and got skipped. The **use** was in `node.c`, which
applied cleanly. A patch is a coherent set; skipping a reject silently breaks that coherence, and you find
out at compile time if you're lucky and at runtime if you're not.

## Why `--fuzz` is worse than failing

```bash
patch -p1 --fuzz=3 < patch-6.1.175   # do not do this
```

`--fuzz` tells `patch` to ignore context lines until a hunk "fits" somewhere. On a tree that has diverged
from mainline — which every device kernel has — it force-fits hunks into the wrong functions. In our case
it appended orphaned code after `unix_bpf_build_proto()` in `net/unix/af_unix.c`, and mis-slotted a
`block/Makefile` hunk. Both compiled. Neither was correct.

**A reject is information. Fuzz destroys that information.** If you find yourself reaching for `--fuzz`,
you are using the wrong tool for the job — which brings us to the right one.

---

## The method that works: merge the ACK tag

ACK publishes a release tag per LTS: `android14-6.1.175_r00`. Merge it. This is what device kernel
maintainers who keep up actually do — their history is full of `Merge branch 'android14-6.1-lts'`.

### 1. You need real history

```bash
git clone https://github.com/<vendor>/<device-kernel>.git   # FULL history — no --depth
```

This is the step people get wrong. A **shallow or squashed** kernel tree has **no merge-base** with ACK, and
without a merge-base `git merge` cannot do a 3-way merge — it has nothing to compare against. If your repo
is a flattened import (a handful of squashed commits), you cannot merge into it at all. Clone the upstream
device kernel *with its history* and work there.

Our tree: 1,189,618 commits, ~2.8 GB. That is the price of admission.

### 2. Fetch just the tag you want

```bash
git remote add ack https://android.googlesource.com/kernel/common
git fetch --no-tags ack refs/tags/android14-6.1.175_r00:refs/tags/android14-6.1.175_r00
```

Incremental — your device kernel's history already contains most of ACK's, so this takes seconds.

### 3. Confirm you have a merge-base

```bash
git merge-base HEAD android14-6.1.175_r00
# 80aded6fbb9d   <- ours; `git show 80aded6fbb9d:Makefile | grep SUBLEVEL` -> 172
```

If this prints nothing, stop — see step 1.

### 4. Merge

```bash
git merge android14-6.1.175_r00
```

Our result:

| | |
|:--|:--|
| commits merged | **1010** |
| files auto-merged cleanly | **838** |
| **conflicts** | **6** |

Six. That is the whole point of this article: **the correct method turns a 33,000-line patch fight into six
files you read by hand.**

### 5. Resolve toward the device side

The principle for every conflict: **the device code wins.** ACK does not know about your hardware; your
vendor tree does. Ours were:

| Conflict | Resolution |
|:--|:--|
| `Documentation/devicetree/bindings` | vendor symlink — keep ours |
| `drivers/pinctrl/qcom/pinctrl-sm8150.c` | different SoC entirely — keep ours |
| `drivers/soc/qcom/llcc-qcom.c` | vendor LLCC slice tables — keep ours |
| `net/qrtr/ns.c` | vendor kthread rewrite — keep ours |
| `kernel/time/hrtimer.c` | vendor offline-enqueue handling that ACK reverted upstream — keep ours |
| `Documentation/.../nvidia,tegra234-mgbe.yaml` | irrelevant to the device — take theirs |

---

## Post-merge fixes

A clean merge is not a building kernel. Two issues, both from the vendor tree diverging:

**1. The hrtimer tracepoint**

```
error: too few arguments to function call, expected 3, have 2
```
ACK widened the `hrtimer_start` tracepoint to three args (adding `was_armed`). The vendor `hrtimer.c` —
which we kept, because it carries device-critical offline-enqueue handling — calls it with two. Since it is
trace plumbing only, revert ACK's change to the header:

```bash
git checkout <vendor-base> -- include/trace/events/timer.h
```

**2. `certs/extract-cert.c` with OpenSSL 3**

ACK guards `key_pass` behind `USE_PKCS11_ENGINE`, but this tree reaches it from the
`#elif defined(HAVE_OPENSSL_ENGINE)` branch. Keep `key_pass` unconditional.

---

## Verify before you believe it

Compiling proves nothing about booting. Two checks that matter:

**Prove you lost nothing.** Diff the resolved defconfig against the old one:

```bash
sym() { grep -E '^(CONFIG_|# CONFIG_)' "$1" | sort; }
diff <(git show OLD:arch/arm64/configs/gki_defconfig | grep -E '^(CONFIG_|# CONFIG_)' | sort) \
     <(sym arch/arm64/configs/gki_defconfig)
```
Match `# CONFIG_x is not set` as well as `CONFIG_x=y` — a symbol silently flipping from *explicitly off* to
*absent* is a real change, and grepping only `^CONFIG` hides it. Anything in the old and missing from the
new is a regression you introduced. Ours: **827 symbols, zero missing.**

**Do not resolve the real config from the defconfig by hand.** A Kconfig `default y` symbol ships without
appearing in the defconfig at all. Only the resolved config is the truth:

```bash
make ARCH=arm64 O=out gki_defconfig
grep -E '^CONFIG_MQ_IOSCHED_KYBER=' out/.config
```

**Boot the bare base first.** Before layering root, SUSFS, a scheduler, anything — boot the merged kernel
alone. If you stack four changes and it bootloops, you have learned nothing. We booted 175 bare, then
175 + BORE + ADIOS, then the root flavors. Each bootloop would have had exactly one candidate cause.

---

## Keep the vendor's boot-safety layer

The thing that makes a device kernel boot is not the LTS version. It is the accumulated device work:

- **Reverts.** Our base carries **6,567** revert commits (`git log --grep='^Revert' | wc -l`) undoing
  upstream changes that break this hardware —
  UFS Qualcomm clock gating, qrtr spinlock waits, DRM valid-clones, PCI/PM reset delays, dwc3. After
  merging, verify the new LTS does not re-introduce what the vendor deliberately reverted.
- **Symlinks and external module dirs** (`arch/arm64/boot/dts/vendor`, `ext-mod-dir`).
- **The device tree and vendor drivers.**

Pure ACK never boots on a phone. It has no device bits. This is not a version problem, and no LTS bump
fixes it. **If you cherry-pick from a vendor base, you will break this. Merge.**

---

## What you cannot automate

Detecting a new ACK tag is mechanical — poll for tags, diff against your pin:

```bash
git ls-remote --tags https://android.googlesource.com/kernel/common 'refs/tags/android14-6.1.*_r00'
```

Everything after that is judgement. The six conflicts needed someone who knew that `pinctrl-sm8150.c` was
a different SoC and that ACK had reverted its own hrtimer change. The `timer.h` revert needed someone to
recognise a tracepoint arity mismatch. No script derives those.

Automate discovery. Never automate the release. **A kernel that compiles is not a kernel that boots**, and
the only thing standing between a user and a bricked phone is somebody having flashed it first.

---

## Summary

| Do | Don't |
|:--|:--|
| Merge ACK's `android14-6.1.NNN_r00` tag | Apply mainline `patch-6.1.x` incrementals |
| Clone the device kernel with full history | Work in a squashed/shallow tree |
| Resolve conflicts toward the device side | Take ACK's side on hardware code |
| Read every reject | `patch --fuzz=3` |
| Boot the bare base before layering | Stack four changes and hope |
| Diff the resolved `.config` | Trust the defconfig |

The result for peridot: **6.1.173 → 6.1.175**, 1010 commits, six conflicts, zero regressions, boots.

---

<sub>

**Theettam Kernel** · [repository](../../) · [releases](../../releases)
Device base: [GuidixX/kernel_xiaomi_sm8635](https://github.com/GuidixX/kernel_xiaomi_sm8635) ·
[ACK](https://android.googlesource.com/kernel/common) ·
[GKI documentation](https://source.android.com/docs/core/architecture/kernel/generic-kernel-image)

</sub>
