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

## accepted-drift.txt (optional, per branch)

A CRC shift that is *known* not to break the stock `vendor_dlkm` — because a
device has booted the shifted Image with every stock module loaded — can be
listed here so the gate stops failing on it without touching the baselines:

```
# <symbol> <new crc>   # evidence
xfrm_register_km 0xdc63593a   # ACK 176 xfrm_mgr change; plain flavor booted 2026-09-03, 445 modules
```

The gate prints such symbols as `ACCEPTED` and still fails on any other
CHANGED/REMOVED symbol. Keep the file on the branch that carries the shift
(it does not exist on `theettam-2.7`, which stays strict), and delete entries
when the baselines are regenerated from a boot-tested build of that branch.
Never add a symbol here on reasoning alone — the whole point of the gate is
that reasoning about KMI has been wrong twice (Rule 2).
