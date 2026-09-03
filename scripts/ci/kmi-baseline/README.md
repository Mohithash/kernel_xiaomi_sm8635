# KMI baselines

One file per flavor: `crc symbol` for every exported symbol in `Module.symvers` of the
**boot-tested** build of that flavor (recorded from tag `v2.6`, Neutron clang 30062026,
plain `gki_defconfig` + the flavor's integration, exactly as `scripts/ci/build-flavor.sh`
builds it).

`build-flavor.sh` diffs every build against its baseline (`scripts/ci/symvers-diff.sh`)
and fails on any CHANGED or REMOVED CRC. Added symbols are allowed. See
`docs/BOOT-NOTES.md` Rule 2 for why: a shifted CRC compiles fine and bootloops because the
stock `vendor_dlkm` modules refuse to load.

Regenerate a baseline only from a build that has actually been boot-tested on the device,
in the same commit as the change that moved the CRC, and say so in the commit message:

    awk '{print $1, $2}' out/Module.symvers | sort -k2 > scripts/ci/kmi-baseline/<flavor>.symvers
