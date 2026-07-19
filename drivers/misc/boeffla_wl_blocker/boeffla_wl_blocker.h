/* SPDX-License-Identifier: GPL-2.0 */
#ifndef _BOEFFLA_WL_BLOCKER_H
#define _BOEFFLA_WL_BLOCKER_H

#define BOEFFLA_WL_BLOCKER_VERSION	"1.1.0-theettam"

/*
 * Default block list for SM8635 / VoltageOS Wi-Fi standby drain.
 * Semicolon-separated; editable at runtime via:
 *   /sys/class/misc/boeffla_wakelock_blocker/wakelock_blocker
 */
#define BOEFFLA_WLBLOCKER_DEFAULTS \
	"qcom_rx_wakelock;wlan;wlan_wow_wl;wlan_extscan_wl;netmgr_wl;IPA_WS;" \
	"NETLINK;ipa;qcom_rx_wakelock;"

#endif /* _BOEFFLA_WL_BLOCKER_H */
