# Root Hiding Guide — peridot (Theettam)

This kernel ships in seven flavors (see the README table). What the kernel itself does
for hiding depends on the flavor:

| Flavor | Kernel-side hiding |
|---|---|
| **KSUN** (plain) | None beyond the baseline rows below — relies on the userspace stack |
| **KSUN + SUSFS**, **SukiSU-Ultra + SUSFS**, **ReSukiSU + SUSFS**, **Premium**, **KSUN + DroidSpaces** | **SUSFS v2.2.0** in-kernel: sus_path / sus_mount / sus_kstat / sus_map, `uname` + cmdline spoof, open-redirect, KSU/SUSFS symbol hiding. Configured from the manager's SUSFS page |
| **APatch** | APatch's own hiding; no SUSFS (that is a KSU-side patch) |

**SELinux is real and enforcing** on every flavor. Nothing in this tree makes the
kernel permissive or fakes the enforcing state: `getenforce` reports what the AVC
actually does. (A "permissive but report enforcing" hack existed in an unreleased
snapshot branch and was deliberately not carried into 2.7.)

## Kernel-side hardening baked into every flavor

| Vector | Status |
|---|---|
| `/proc/config.gz` leaking `CONFIG_KSU` | Closed since 2.7 — `IKCONFIG_PROC` off (`IKCONFIG` stays on so `scripts/extract-ikconfig` still works on the Image). 2.6 and earlier exposed it |
| Custom version string, `+` suffix | Stock GKI `LOCALVERSION` (`-android14-11-ga3b9c44908dd-ab13320413`); `LOCALVERSION_AUTO=n` removes the `+` |
| Build user/host in `/proc/version` | `build@localhost` (set by CI and by `scripts/ci/build-flavor.sh`) |
| `uname()` for Play Services | `CONFIG_UNAME_OVERRIDE` serves `com.google.android.gms` the stock `6.1.118-android14-11-ga3b9c44908dd-ab13320413` string |
| DirtySepolicy canaries (`fsck_untrusted` CAP_SYS_ADMIN, `adbd→adbroot`) | Reported as denied to apps by `selinux_hide` on all KSU-family flavors (grafted by `scripts/susfs/integrate*.sh`); the live rules keep working |

## Userspace stack (flash on top, in order)

1. **Zygisk provider** — ReZygisk (KernelSU-Next has none built in; SukiSU-Ultra ships one).
2. **Shamiko** — hides root/mounts from apps.
   - Add target apps to the manager's **deny list**, but leave **"Enforce Deny List" OFF**.
     Shamiko does the hiding; enabling both makes it worse.
3. **Play Integrity**
   - **PlayIntegrityFix** (a currently maintained fork) → BASIC + DEVICE.
   - **TrickyStore** + a valid `keybox.xml` → STRONG. Keyboxes get revoked over time;
     refresh when STRONG stops passing.
4. **App profiles** — enable **"Umount modules"** for sensitive apps (and as the default
   for new apps); deny root entirely for apps that never need it.
5. **SUSFS flavors** — in the manager's SUSFS page add sus paths/mounts for your modules;
   the kernel does the rest.

## LSPosed

- Use the **maintained fork** (JingMatrix/LSPosed). Flash as a Zygisk module.
- **Hide/randomize the LSPosed manager** package name in its settings.
- LSPosed still injects into hooked apps regardless of the deny list; use Shamiko to hide
  *root* from those apps. Re-test after each change.

## General hygiene

- **Hide/repackage the manager** — its default package is a known detection target.
- **Keep modules minimal** — every module that mounts into `/system` adds detection surface.
- **Match manager ↔ kernel** — use the manager build that pairs with your flavor's driver
  (pins in `scripts/ci/pins.env`).

## Verify (don't guess)

- **Play Integrity API Checker** — confirms BASIC / DEVICE / STRONG.
- **Momo**, **Ruru**, **Native Detector** — general root-detection tests.

Check before *and* after each change so you know what actually moved the needle.
