# Theettam Trip Mode

**Calls and SMS only.** Everything else off. For trips, or any day the battery has
to last longer than the phone does.

```sh
trip.sh on       # radios and background off
trip.sh off      # exactly as it was
trip.sh status
```

Two modes, independent:

| | |
|---|---|
| **`trip.sh on`** | data, wifi, BT, sync, location off. Kernel wakelock blocker armed. Calls and SMS still arrive. |
| **service.sh** *(automatic)* | just arms the kernel blocker on screen-off, clears it on screen-on. Everything keeps working; the phone only sleeps harder. |

Use the daemon daily; flip trip mode on when you need two days out of one charge.

## How this compares to Frosty

[Frosty](https://github.com/Drsexo/Frosty) is the most advanced module in this space
and is 3,640 lines across 19 scripts. This is ~110. The difference is not cleverness,
it is that two of its hardest problems do not exist here:

**Its `gms_freeze.sh` does not apply to you.** It runs `pm disable` on individual
Google Play services components -- surgery on *privileged* GMS, which is why its
README warns about breaking Maps, Find My Device, Pay and NFC. Under sandboxed Play
(GrapheneOS-style, as on VoltageOS) GMS is an ordinary user app with no privileged
services to dissect. Turn data off and it stops, like any other app. That entire
file and its breakage evaporate.

**Its wakelock killer cannot see the wakelocks that matter.** It greps `dumpsys
power`, which lists only userspace wakelocks, then `am force-stop`s whoever holds
one. The wakelocks that keep a Snapdragon awake are held by *drivers* -- `IPA_WS`,
`rmnet_ipa%d`, `RMNET_SHS` -- invisible to `dumpsys` and unreachable from userspace
at any privilege. Your kernel refuses them in `wakeup_source_activate()`. That is
the half no module can do, and it is why this one checks for the kernel and aborts
without it.

One more thing worth knowing: Frosty never checks whether you are on a call before
pulling radios. `trip.sh` does.

## Why this is not another battery module

Every other one — Frosty, Greenify, the GMS Doze family — parses `dumpsys power`
and runs `am force-stop` on whatever it finds. That has two problems:

1. `dumpsys power` only shows **userspace** wakelocks. The ones that actually keep a
   Snapdragon awake are held by drivers: `IPA_WS`, `rmnet_ipa%d`, `RMNET_SHS`. They
   are invisible there and unreachable from userspace at any privilege level.
2. `force-stop` **destroys** the app. State gone, alarms cancelled, and it relaunches
   on the next broadcast — so you pay the restart cost you were trying to avoid.

This module does neither. The kernel refuses the wakelock in
`wakeup_source_activate()` before it ever counts, so the driver simply does not get
to keep the AP awake. That only works on a kernel carrying the blocker, which is
why this module refuses to install without one.

## What it does

| | |
|---|---|
| Screen off | writes the data-path list to the kernel blocker |
| Screen on | clears it — messages arrive normally while you are using the phone |
| Charging | clears it — nothing to save on a charger |
| Calls / SMS | untouched: those arrive on the modem's control path, not the data path |
| Alarms | untouched: `alarmtimer`/RTC is never blocked |

Blocking only while the screen is off is the whole design. Block the data path
permanently and your messages are late all day; block it overnight and the phone
sleeps.

## Requires

A kernel with `CONFIG_BOEFFLA_WL_BLOCKER=y` — Theettam Kernel has it. The module
checks at install and aborts rather than silently doing nothing.

## Config

`/data/adb/modules/theettam_trip/trip.conf` — the list, poll interval, charger
behaviour. Find your own worst offenders with `scripts/wakestat/wakestat.sh`.

## What it does not do yet

Freeze apps. That needs `BINDER_FREEZE` — an ioctl, so it needs a compiled helper
rather than shell, and it is the deadlock-safe path Android itself uses for cached
apps. Planned for v2. The wakelock half stands alone and is the half your kernel
uniquely enables.

## Credit

The blocker is **andip71's Boeffla wakelock blocker v1.1.0**, carried in the device
kernel tree. This module only decides when to arm it.
