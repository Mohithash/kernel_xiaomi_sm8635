# Release note template

Copy the block below into the GitHub Release body. Everything in `<ANGLE
BRACKETS>` gets filled in or deleted; no bracket survives into the published
text. The point of this template is the **Boot status** table: every flavor
gets an explicit, checkable claim about whether a real device booted it, not
a blanket "tested" that quietly means "compiled". docs/RELEASE-CHECKLIST.md is
what has to be true before you fill this in; docs/telegram-post.md's "Rules
that keep the post honest" apply here too, this is the longer-form counterpart
of that post.

Run `scripts/device/postflash-check.sh` for every row marked **Boot-tested**
and keep its output: link it or paste the verdict line, do not assert PASS
from memory.

---

```markdown
## Theettam <VERSION> "<EDITION NAME>" — <YYYY-MM-DD>

Base: GKI `android14-6.1.<SUBLEVEL>` + GuidixX `<BRANCH>` @ `<SHORT-SHA>`
Built from `<branch>` @ `<commit-sha>` with Neutron clang `<NEUTRON_BUILD>`.
Pins: `scripts/ci/pins.env` @ this commit (SUSFS `<SUSFS_EXPECT_VERSION>`,
KernelSU-Next `<KSUN_TAG>`, SukiSU-Ultra `<short-sha>`, KernelPatch `<KP_VERSION>`).

### Boot status

<!-- One row per flavor published in this release. "Boot-tested" means
     postflash-check.sh exited 0 on a real device for THIS build, not "a past
     release with a similar config booted". "Compile-verified only" means the
     CI KMI gate passed (changed=0 removed=0, or only ACCEPTED shifts, against
     scripts/ci/kmi-baseline/<flavor>.symvers) and nothing more; say so plainly. -->

| Flavor | Status | Evidence |
|---|---|---|
| KSUN (`ksun-plain`) | <✅ Boot-tested \| 🧪 Compile-verified only> | <postflash-check verdict / link, or "KMI gate: changed=0 removed=0"> |
| KSUN + SUSFS (`ksun-susfs`) | <status> | <evidence> |
| SukiSU-Ultra + SUSFS (`sukisu-susfs`) | <status> | <evidence> |
| ReSukiSU + SUSFS (`resukisu-susfs`) | <status> | <evidence> |
| KSUN + DroidSpaces (`ksun-susfs-droidspaces`) | <status> | <evidence> |
| Premium (`premium`) | <status> | <evidence> |
| APatch (`apatch`) | <status, or "not built this release: no superkey supplied"> | <evidence> |

<!-- plain (NoRoot) is built and KMI-gated in CI but never published; if you
     boot-tested it as the baseline (checklist step 2), say so as a line, not a
     table row, since no zip is attached to it: -->
`plain` (NoRoot, not published, KABI baseline): <✅ boot-tested, postflash-check exit 0 | not run this release>

### Boot-tested on

<PHONE / ROM build, e.g. "POCO F6 (peridot, 24069PC21I), HyperOS <version>, real
device over adb">. VoLTE call: <placed and received, audio both ways ✅ |
not tested, say so, do not omit it>. 10-minute screen-off drain: <n%, against
<previous release>'s n% | not run>.

### What's new

<!-- From the real diff against the previous tag (docs/RELEASE-CHECKLIST.md
     step 6 has the commands), not copied from the last release. Only what
     changed THIS release; inherited device-base tuning is credit, not a
     bullet (docs/telegram-post.md rule 2). -->

- <bullet>
- <bullet>

### Known issues / gaps in validation

<!-- Be as specific as docs/BOOT-NOTES.md is about its own reasoning; "may
     have minor issues" is worse than naming the gap. Examples from this
     tree's own history, delete what does not apply: -->

- <e.g. "Built from theettam-2.7-lts176: three exported CRCs differ from the
  6.1.175 baselines (km_migrate, xfrm_register_km, xfrm_unregister_km, ACK
  176's xfrm_mgr change). Listed in kmi-baseline/accepted-drift.txt because
  the plain flavor booted with all 445 stock vendor modules on 2026-09-03;
  dmesg was not readable on that no-root boot, so oops-free is confirmed only
  for the rooted flavors named Boot-tested above.">
- <only the flavors marked Boot-tested were verified on hardware; every other
  flavor's confidence is exactly "it compiled and its exported-symbol CRCs
  match a flavor that did boot", which is real but not the same claim.>

### Flash instructions

AnyKernel3 zip, flash `Image` only; stock `vendor_dlkm` stays
(docs/BOOT-NOTES.md Rule 7). Back up `boot.img` and `vendor_boot.img` first.
Flash at your own risk.

### Credits

Fork of Chidori Kernel by @guidix_m; device support and base tuning are
theirs. BORE/ADIOS: firelzrd. SUSFS: simonpunk. Root engines: KernelSU-Next,
SukiSU-Ultra, ReSukiSU, KernelPatch.
```

---

## Before publishing

- [ ] Every **Boot status** row is either ✅ with `postflash-check.sh` evidence
      attached or linked, or explicitly 🧪 compile-verified only. No row left
      ambiguous.
- [ ] **What's new** came from `git log`/`git diff` against the previous tag.
- [ ] **Known issues** names the actual gap (which flavors were not
      boot-tested, which KMI symbols shifted and why that is accepted).
- [ ] VoLTE and screen-off drain are filled in or marked "not tested", never
      silently dropped.
- [ ] docs/telegram-post.md updated from the same diff, before or alongside
      publishing; the two must not disagree about what shipped.
