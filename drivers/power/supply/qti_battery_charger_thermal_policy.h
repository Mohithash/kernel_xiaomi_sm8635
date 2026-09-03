#ifndef _QTI_BATTERY_CHARGER_THERMAL_POLICY_H
#define _QTI_BATTERY_CHARGER_THERMAL_POLICY_H

#include <linux/workqueue.h>
#include "qti_battery_charger.h"

static int battery_psy_set_charge_current(struct battery_chg_dev *bcdev, int val);

static int battery_chg_calc_fastcharge_mode(u32 sport_mode, u32 smart_chg)
{
	if (sport_mode == 1 && smart_chg == 8)
		return 2;
	if (sport_mode == 0 && smart_chg == 8)
		return 1;
	return 0;
}

static int battery_chg_get_fastcharge_mode(struct battery_chg_dev *bcdev, int *mode)
{
	struct psy_state *pst = &bcdev->psy_list[PSY_TYPE_XM];
	int rc;
	u32 sport_mode;
	u32 smart_chg;

	rc = read_property_id(bcdev, pst, XM_PROP_SPORT_MODE);
	if (rc < 0)
		return rc;
	sport_mode = pst->prop[XM_PROP_SPORT_MODE];

	rc = read_property_id(bcdev, pst, XM_PROP_SMART_CHG);
	if (rc < 0)
		return rc;
	smart_chg = pst->prop[XM_PROP_SMART_CHG];

	*mode = battery_chg_calc_fastcharge_mode(sport_mode, smart_chg);
	bcdev->fastcharge_mode_cache = *mode;

	return 0;
}

static int battery_chg_get_temp_decic(struct battery_chg_dev *bcdev, int *temp_decic)
{
	struct psy_state *pst = &bcdev->psy_list[PSY_TYPE_BATTERY];
	int rc;

	rc = read_property_id(bcdev, pst, BATT_TEMP);
	if (rc < 0)
		return rc;

	/* BATT_TEMP is reported in 0.01C; convert to 0.1C for thresholds. */
	*temp_decic = DIV_ROUND_CLOSEST((int)pst->prop[BATT_TEMP], 10);
	return 0;
}

static int battery_chg_calc_ctrl_idx(int temp_decic, int mode)
{
	if (mode == 0) {
		/* Slow Mode */
		if (temp_decic >= 430) return 16;
		if (temp_decic >= 410) return 15;
		if (temp_decic >= 390) return 14;
		return 13;
	} else if (mode == 1) {
		/* Normal / Smart Charging Mode */
		if (temp_decic >= 450) return 16;
		if (temp_decic >= 430) return 14;
		if (temp_decic >= 410) return 12;
		if (temp_decic >= 400) return 10;
		if (temp_decic >= 390) return 8;
		if (temp_decic >= 380) return 6;
		if (temp_decic >= 370) return 4;
		if (temp_decic >= 360) return 2;
		return 0;
	} else {
		/* Sport / Turbo Charging Mode */
		if (temp_decic >= 460) return 16;
		if (temp_decic >= 430) return 14;
		if (temp_decic >= 420) return 9;
		if (temp_decic >= 410) return 6;
		if (temp_decic >= 400) return 4;
		if (temp_decic >= 390) return 2;
		if (temp_decic >= 380) return 1;
		return 0;
	}
}

static void battery_chg_ctrl_limit_work(struct work_struct *work)
{
	struct battery_chg_dev *bcdev = container_of(work,
							struct battery_chg_dev,
							chg_ctrl_limit_work.work);
	struct psy_state *pst = &bcdev->psy_list[PSY_TYPE_BATTERY];
	struct psy_state *pst_xm = &bcdev->psy_list[PSY_TYPE_XM];
	struct psy_state *pst_usb = &bcdev->psy_list[PSY_TYPE_USB];
	unsigned int delay_ms = CHG_CTRL_LIMIT_INTERVAL_MS;
	int temp_decic;
	int mode = 1;
	int idx;
	int max_level;
	int rc;
	int rc1, rc2;
	int start_limit;
	u32 current_limit;
	bool charging_full = false;

	if (bcdev->chg_ctrl_stopping)
		return;

	if (!bcdev->initialized)
		goto resched;

	if (bcdev->num_thermal_levels <= 0)
		goto resched;

	/*
	 * There is no charge rate to throttle while unplugged. Every tick
	 * costs several synchronous glink round trips and each one holds a
	 * wakeup source, so idle polling is what keeps the system awake.
	 * Poll slowly, just often enough to notice the next attach.
	 */
	rc = read_property_id(bcdev, pst_usb, USB_ONLINE);
	if (rc < 0)
		goto resched;

	if (pst_usb->prop[USB_ONLINE] != 1) {
		if (bcdev->chg_ctrl_thermal_suspend &&
		    !write_property_id(bcdev, pst_xm, XM_PROP_INPUT_SUSPEND, 0))
			bcdev->chg_ctrl_thermal_suspend = false;

		bcdev->chg_ctrl_last_idx = -1;
		bcdev->chg_ctrl_last_mode = -1;
		delay_ms = CHG_CTRL_LIMIT_IDLE_INTERVAL_MS;
		goto resched;
	}

	max_level = bcdev->num_thermal_levels - 1;

	rc = battery_chg_get_temp_decic(bcdev, &temp_decic);
	if (rc < 0)
		goto resched;

	/*
	 * Check if battery charging has reached the full threshold.
	 * If charging is full, clear INPUT_SUSPEND so the device can suspend.
	 * This takes priority over temperature-based suspend management.
	 * Uses the actual end threshold property instead of hardcoded value.
	 * Compares end threshold to start threshold to detect if user set a limit.
	 */
	rc1 = read_property_id(bcdev, pst, BATT_CHG_CTRL_END_THR);
	if (!rc1)
		current_limit = pst->prop[BATT_CHG_CTRL_END_THR];
	rc2 = read_property_id(bcdev, pst, BATT_CHG_CTRL_START_THR);
	if (!rc2)
		start_limit = pst->prop[BATT_CHG_CTRL_START_THR];
	if (!rc1 && !rc2 && current_limit > start_limit && current_limit > 50) {
		/*
		 * User has set a charge limit (end > start, both > 50%).
		 * Assume charging has reached its limit and clear INPUT_SUSPEND
		 * so the device can suspend. This works for any threshold the user sets
		 * (80%, 90%, 95%, etc.).
		 */
		charging_full = true;
	}

	/*
	 * Emergency thermal protection: hardware lockup fallback.
	 *
	 * INPUT_SUSPEND is shared with userspace - the health HAL asserts it
	 * to hold the battery at its charge limit. Only drop a suspend that
	 * this work put there itself, otherwise the two fight: the HAL sets
	 * the limit, we clear it, charging resumes, the HAL sets it again.
	 * That ping-pong churns charger state every few seconds, and each
	 * change fires power_supply_changed() -> wakeup source + uevent,
	 * which stops the device suspending while it sits on the charger.
	 */
	if (temp_decic >= 465) {
		rc = read_property_id(bcdev, pst_xm, XM_PROP_INPUT_SUSPEND);
		if (!rc && pst_xm->prop[XM_PROP_INPUT_SUSPEND] == 0) {
			pr_err("CRITICAL THERMAL LEVEL! Enabling INPUT_SUSPEND fallback\n");
			if (!write_property_id(bcdev, pst_xm, XM_PROP_INPUT_SUSPEND, 1))
				bcdev->chg_ctrl_thermal_suspend = true;
		}
	} else if (temp_decic <= 430 && bcdev->chg_ctrl_thermal_suspend) {
		pr_info("Temperature recovered. Disabling INPUT_SUSPEND fallback\n");
		if (!write_property_id(bcdev, pst_xm, XM_PROP_INPUT_SUSPEND, 0))
			bcdev->chg_ctrl_thermal_suspend = false;
	}

	/*
	 * If charging is full (reached 95% limit), clear INPUT_SUSPEND
	 * so the device can suspend. This overrides temperature-based logic
	 * when charging has completed.
	 */
	if (charging_full && bcdev->chg_ctrl_thermal_suspend) {
		pr_info("Charging full. Disabling INPUT_SUSPEND for suspend\n");
		if (!write_property_id(bcdev, pst_xm, XM_PROP_INPUT_SUSPEND, 0))
			bcdev->chg_ctrl_thermal_suspend = false;
	}

	rc = battery_chg_get_fastcharge_mode(bcdev, &mode);
	if (rc < 0)
		mode = 1;

	idx = battery_chg_calc_ctrl_idx(temp_decic, mode);
	if (idx > max_level)
		idx = max_level;

	/*
	 * Periodically check the actual charging limit set in firmware.
	 * Hardware or other services might reset it during PD renegotiation
	 * or charger re-plug, allowing current to spike up again.
	 */
	rc = read_property_id(bcdev, pst, BATT_CHG_CTRL_LIM);
	if (!rc) {
		current_limit = pst->prop[BATT_CHG_CTRL_LIM];
		if (current_limit != idx) {
			pr_debug("Charge limit altered by firmware! Re-applying. (old: %u, expected: %d)\n", current_limit, idx);
			bcdev->chg_ctrl_last_idx = -1; /* Force update */
		}
	}

	if (idx != bcdev->chg_ctrl_last_idx || mode != bcdev->chg_ctrl_last_mode) {
		battery_psy_set_charge_current(bcdev, idx);
		bcdev->chg_ctrl_last_idx = idx;
		bcdev->chg_ctrl_last_mode = mode;
	}

resched:
	/*
	 * Re-check before re-arming: this work requeues itself, so a lone
	 * cancel_delayed_work_sync() in remove()/error teardown can race with
	 * an instance that is about to schedule the next one.
	 */
	if (bcdev->chg_ctrl_stopping)
		return;

	schedule_delayed_work(&bcdev->chg_ctrl_limit_work,
				msecs_to_jiffies(delay_ms));
}

#endif /* _QTI_BATTERY_CHARGER_THERMAL_POLICY_H */
