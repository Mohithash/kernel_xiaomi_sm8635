# Telegram channel post

The release announcement for the Theettam Kernel channel, kept in the repo so it
stays in sync with what actually shipped. Copy the block below verbatim.

**Rules that keep the post honest** (learned the hard way — an earlier draft
advertised CAKE and IPv6 NAT, neither of which is compiled in):

1. **Every feature claim must be checkable.** Before posting, resolve the real
   config the way the build does and grep it:
   ```bash
   make ARCH=arm64 O=/tmp/cfg gki_defconfig
   grep -E '^CONFIG_(NET_SCH_CAKE|SCHED_BORE|MQ_IOSCHED_ADIOS)=' /tmp/cfg/.config
   ```
   A symbol being `default y` in Kconfig means it ships even when the defconfig
   never mentions it — and a symbol in the defconfig can still be overridden. Only
   the resolved `.config` is the truth.
2. **Highlights list what this fork adds.** Tuning inherited from the device base
   belongs under Notes as credit, not in Highlights as if it were ours.
3. **Credit the code you ship.** Chidori/GuidixX for the base, firelzrd for
   BORE/ADIOS, simonpunk for SUSFS, the root projects for their drivers.
4. **Never announce an unbooted build.** Compile-verified is not boot-verified.

---

```
#Theettam #Kernel #Peridot #AOSP #Android16 #KernelSUNext #KernelSU #SUSFS #SukiSU #ReSukiSU #GKI #ACK #Linux #AndroidKernel #PocoF6

**Theettam Kernel v2.0 "Neetti Vali" Edition | Android 16**
Updated: 17/07/'26

▪️ **Download**
• [KernelSU-Next](https://github.com/Mohithash/kernel_xiaomi_sm8635/releases/download/v2.0/Theettam-2.0-KSUN3.3.0-peridot-6.1.175-android14-11-ga3b9c44908dd-ab13320413.zip)
• [KernelSU-Next + SUSFS v2.2.0](https://github.com/Mohithash/kernel_xiaomi_sm8635/releases/download/v2.0/Theettam-2.0-KSUN3.3.0-SUSFS2.2.0-peridot-6.1.175-android14-11-ga3b9c44908dd-ab13320413.zip)
• [SukiSU Ultra + SUSFS v2.2.0](https://github.com/Mohithash/kernel_xiaomi_sm8635/releases/download/v2.0/Theettam-2.0-SukiSU-Ultra-SUSFS2.2.0-KPM-peridot-6.1.175-android14-11-ga3b9c44908dd-ab13320413.zip)
• [ReSukiSU + SUSFS v2.2.0](https://github.com/Mohithash/kernel_xiaomi_sm8635/releases/download/v2.0/Theettam-2.0-ReSukiSU-SUSFS2.2.0-peridot-6.1.175-android14-11-ga3b9c44908dd-ab13320413.zip)

▪️ **ChangeLogs** — [full release notes](https://github.com/Mohithash/kernel_xiaomi_sm8635/releases/tag/v2.0)

**What this fork adds:**
• **Linux GKI 6.1.175** — first LTS bump past 6.1.173 for peridot, via a real 3-way merge of ACK `android14-6.1-lts` (1010 commits)
• **KernelSU-Next v3.3.0 + SUSFS v2.2.0** — hand-authored port; this pairing does not exist upstream
• **SukiSU Ultra + SUSFS v2.2.0** (with KPM) and **ReSukiSU + SUSFS v2.2.0**
• **BBRv3 + PLB** congestion control
• **BORE** CPU scheduler — `sysctl kernel.sched_bore=0` to disable at runtime
• **ADIOS** I/O scheduler (default)
• **Stock uname** — reports a stock GKI version string, no custom kernel branding

**Notes:**
• Fork of **Chidori Kernel by @guidix_m** — full credit to the original project. Device support and the kernel tuning (MGLRU, fq_codel, WireGuard, UCLAMP, HZ=300, Play Integrity uname override) come from there.
• **BORE** and **ADIOS** by Masahito Suzuki (firelzrd). **SUSFS** by simonpunk. Root engines by their respective projects.

**IMPORTANT:**
• Backup boot.img & vendor_boot.img before flashing.
• Flash at your own risk.

Maintainer: @couponxdealer

Follow @PocoF6GlobalUpdate
Join @PocoF6Official
```

---

## Updating for the next release

- Bump the version, date, and the four download links (the filenames carry
  `kernel.release`, so they change on every LTS bump).
- Rewrite **What this fork adds** from the actual diff against the previous tag —
  not from the last post. Copying the previous changelog forward is how phantom
  features like CAKE survive for releases at a time.
- Keep **Notes** intact unless the credits genuinely change.
