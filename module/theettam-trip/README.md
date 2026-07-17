# Theettam Trip Mode

Blocks the modem **data-path** wakelocks while the screen is off. Calls, SMS and
alarms keep working.

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
