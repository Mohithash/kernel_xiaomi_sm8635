# Release checklist

What must be true before a CI-built zip is published as a **Release** (not the
automatic `ci-2.7-<run>` prerelease that `build-theettam.yml` tags on a
`workflow_dispatch` with `release=true`; that one is labelled
"compile-verified, untested" and is not what this checklist gates).

One maintainer, one phone. Every step is something you can do alone in an
evening; nothing here assumes a device farm.

- [ ] **1. Every flavor is green in CI for the exact commit being released.**
  Open the `Theettam — build all flavors` run for that SHA and confirm these
  jobs succeeded: `plain`, `ksun-plain`, `ksun-susfs`, `sukisu-susfs`,
  `ksun-susfs-droidspaces`, `resukisu-susfs`, `premium`, and, **only if** you
  supplied `apatch_superkey` for this run, `apatch`. Without a superkey there
  is no `apatch` job and no APatch zip for this release; do not reuse an
  `Image-apatch` from an earlier run, it was not built from this commit.

  `build-flavor.sh` treats a KMI CRC drift as a hard failure and CI runs it with
  `KMI_STRICT=1`, so a green job already means `changed=0 removed=0` against
  `scripts/ci/kmi-baseline/<flavor>.symvers` (docs/BOOT-NOTES.md Rule 2), or
  only shifts listed in that branch's `kmi-baseline/accepted-drift.txt`, which
  the log prints as `ACCEPTED`. Still eyeball the build step's
  `KMI gate: SUMMARY ...` line per flavor: a green badge says it passed, not
  what it compared against.

  `plain` (NoRoot) is built and gated like the others but never zipped and
  never published: it is the KABI baseline / bisect flavor. Its `Image-plain`
  is in the `build-plain` artifact for step 2.

- [ ] **2. `scripts/device/postflash-check.sh` PASSes on the real device for at
  least `plain` and one root+SUSFS flavor (`sukisu-susfs` or `ksun-susfs`).**
  These isolate the two independent ways this fork breaks boot: `plain` is the
  bare device base + LTS bump + non-root patches, so a failure there is the
  *merge itself*; the root flavor covers the driver graft. Flash each `Image`
  (AnyKernel3, Image only, docs/BOOT-NOTES.md Rule 7), then:

  ```bash
  adb push scripts/device/postflash-check.sh /data/local/tmp/
  adb shell sh /data/local/tmp/postflash-check.sh "<kernel.release>" <flavor> | tee postflash-<flavor>.txt
  ```

  `<kernel.release>` is `out/include/config/kernel.release` from the build, or
  the `6.1.NNN-android14-11-g...` part of the zip name. The exit code must be 0.
  On the root flavor the script picks up `su` on its own, so `dmesg-clean`,
  `io-scheduler` and `susfs-evidence` become real checks instead of SKIPs; on
  `plain` those stay SKIP and that is expected. A FAIL on anything other than
  `wifi-on`/`bt-on` (if you deliberately turned them off) blocks the release
  until explained. Keep the reports and paste the verdict lines into the
  release notes (docs/RELEASE-TEMPLATE.md).

  If you can sweep more flavors (`premium` and `ksun-susfs-droidspaces` add the
  DroidSpaces namespace checks), do; this is a floor.

- [ ] **3. A real VoLTE call, placed *and* received, with audio both ways.**
  `postflash-check.sh`'s `telephony-*` checks only confirm registration state,
  and SKIP entirely with no SIM inserted (they did on 2026-09-03: an empty SIM
  slot looks like OUT_OF_SERVICE and proves nothing either way). Registration
  is necessary, not sufficient: this fork has broken calls with a change that
  looked unrelated (`DEBUG_INFO_BTF=n` in the disowned `peridot-6.1.175`
  snapshot broke netd/IMS; the first Premium alpha broke calls the same way,
  see README's Premium section and docs/BOOT-NOTES.md Rule 0). Do the call on
  every flavor you boot-test in step 2.

- [ ] **4. Ten-minute screen-off drain sanity.**
  Note the battery level (`adb shell dumpsys battery | grep level`), lock the
  screen, leave it alone for 10 minutes with wifi and cellular connected (not
  airplane mode: the point is to catch a live wakelock regression). Compare
  the drop with the previous release under the same conditions. There is no
  single right threshold, but a release that drains noticeably faster is the
  signal to chase before shipping. If it looks off, check
  `adb shell dumpsys power | grep -A5 'Wake Lock'` and docs/BOOT-NOTES.md Rule
  9's Boeffla note: a silently populated `LIST_WL_DEFAULT` blocks modem/IPA/
  bluetooth wakelocks and looks exactly like "better battery, worse
  connectivity".

- [ ] **5. Public text matches `scripts/ci/pins.env`.**
  ```bash
  grep -E '^(SUSFS_EXPECT_VERSION|KSUN_TAG|KP_VERSION|NEUTRON_BUILD)=' scripts/ci/pins.env
  grep -n 'SUSFS-v\|GKI-6\.1\|v3\.' README.md | head
  ```
  README's badges (`GKI-6.1.175`, `SUSFS-v2.3.0`) and the flavor table's
  version column are where this has drifted before; docs/telegram-post.md's
  honesty rules exist because a post once advertised CAKE and IPv6 NAT that
  were not compiled in. Also confirm docs/BOOT-NOTES.md's TL;DR and Rule 10
  match the branch you are releasing from (`theettam-2.7` is SUBLEVEL 175;
  `theettam-2.7-lts176` is 176 and carries `kmi-baseline/accepted-drift.txt`).

- [ ] **6. Changelog drafted from the real diff, not copied forward.**
  There is no separate `CHANGELOG.md`: the changelog is the GitHub Release body
  (docs/RELEASE-TEMPLATE.md) plus docs/telegram-post.md. Do not start a third
  place for it. Diff against the previous release tag:
  ```bash
  git log --oneline <previous-tag>..<this-commit> -- ':!*.md' ':!docs' ':!assets'
  git diff <previous-tag>..<this-commit> -- scripts/ci/pins.env
  ```
  Fill in docs/RELEASE-TEMPLATE.md from that, and update docs/telegram-post.md
  per its own "Updating for the next release" section. Its rule 4, "never
  announce an unbooted build", is what step 2 makes true.

---

Order: 1 (CI green) before 2 (you need the Images), 2/3/4 are the
device-in-hand work, 5/6 can run in parallel with them. None of this replaces
docs/BOOT-NOTES.md: that is about why a change is safe before a device sees
it; this is about proving it afterwards.
