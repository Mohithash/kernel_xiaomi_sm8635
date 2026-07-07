# Root Hiding Guide — peridot (KernelSU-Next)

This kernel uses **KernelSU-Next v3.3.0** (unified tracepoint + syscall-table hook
engine). It does **not** use SUSFS by design — deep mount/prop hiding is handled in
userspace instead, which is lower-risk and easier to maintain.

## Kernel-side hardening already baked in

| Vector | Status |
|---|---|
| `/proc/config.gz` leaking `CONFIG_KSU` | Closed — `IKCONFIG`/`IKCONFIG_PROC` disabled |
| Custom version string (`Chidori`, `+`) | De-branded to stock GKI-style `LOCALVERSION`; empty `.scmversion` removes the `+` |
| Build user/host in `/proc/version` | Set to `build@localhost` |
| `uname()` for Play Services | Spoofed to a stock string via `CONFIG_UNAME_OVERRIDE` (upstream feature) |

## Userspace stack (flash on top, in order)

1. **ReZygisk** — Zygisk provider (KSU-Next has none built-in). Required by the rest.
2. **Shamiko** — hides root/mounts from apps.
   - In the KSU-Next manager, add target apps to the **deny list**, but leave
     **"Enforce Deny List" OFF**. Shamiko does the hiding; enabling both makes it worse.
3. **Play Integrity**
   - **PlayIntegrityFix** (use a currently-maintained fork) → BASIC + DEVICE.
   - **TrickyStore** + a valid `keybox.xml` → STRONG. Keyboxes get revoked over time;
     refresh when STRONG stops passing.
4. **KSU-Next app profiles** — enable **"Umount modules"** for sensitive apps (and as
   the default for new apps); deny root entirely for apps that never need it.

## LSPosed

- Use the **maintained fork** (JingMatrix/LSPosed) — the original is abandoned. Flash as
  a Zygisk module (ReZygisk must be enabled).
- **Hide/randomize the LSPosed manager** package name in its settings.
- LSPosed still injects into hooked apps regardless of the deny list; use Shamiko to hide
  *root* from those apps. Re-test after each change.

## General hygiene

- **Hide/repackage the KSU-Next manager** — its default package is a known detection target.
- **Keep modules minimal** — every module that mounts into `/system` adds detection surface.
- **Match manager ↔ kernel** — use the KSU-Next v3.3.0 manager with the v3.3.0 kernel module.

## Verify (don't guess)

- **Play Integrity API Checker** — confirms BASIC / DEVICE / STRONG.
- **Momo**, **Ruru**, **Native Detector** — general root-detection tests.

Check before *and* after each change so you know what actually moved the needle.
