# CALLSAFE test Image — what changed

Flash this **instead of** the old Premium (IMS broken) and **instead of** full DS with USER_NS.

## Modified vs broken premium

| Item | Broken premium | This CALLSAFE test |
|------|----------------|-------------------|
| SukiSU + KPM + SUSFS | yes | yes |
| SYSVIPC + KABI relocate | yes | yes |
| PID_NS | yes | yes |
| DEVTMPFS | yes | yes |
| XT_MATCH_ADDRTYPE | yes | yes |
| **USER_NS** | **yes** | **NO** |
| FW_LOADER_COMPRESS | yes | **NO** |
| NF_CT_NETLINK in fragment | yes (already on base) | not forced |
| IPC_NS / POSIX_MQUEUE | missing | **on** (POSIX already base) |
| PELT 8ms | yes | **stock 16ms** |
| qcom_rx wakelock block | yes | **removed** |
| ZRAM multi-comp | yes | **off** |

## How to test

1. Flash zip in OrangeFox (Image-only).
2. Boot, open SukiSU Ultra.
3. Place a **Jio voice call**.
4. Optional: `adb shell` → dialer should not show "Explicit network reject"; status bar VoLTE if usual.

### Pass
Calls work → USER_NS / Category A / extras were the problem. Keep CALLSAFE; add USER_NS later in a second zip if you want.

### Fail
Calls still die → next bisect: drop PID_NS or SYSVIPC one at a time, or try `droidspaces-v1` (KSUN+old DS).

## Rebuild flags

```bash
# this default
SKIP_DROIDSPACES=0 PREMIUM_FULL_DS=0 bash theettam/scripts/build_premium_sukisu.sh

# old full DS (USER_NS on) — expect call risk
PREMIUM_FULL_DS=1 bash theettam/scripts/build_premium_sukisu.sh

# 2.1-like no containers
SKIP_DROIDSPACES=1 bash theettam/scripts/build_premium_sukisu.sh
```

## Existing zips to compare (no wait)

| Zip | Role |
|-----|------|
| Theettam **2.1 SukiSU** | Calls OK baseline |
| **droidspaces-v1** | KSUN + old DS fragment — test if DS alone kills calls |
| **premium KSU-FIXED** | Known bad for Jio voice |