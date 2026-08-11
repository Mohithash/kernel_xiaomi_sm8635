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
	int temp_decic;
	int mode = 1;
	int idx;
	int max_level;
	int rc;
	u32 current_limit;

	if (!bcdev->initialized)
		goto resched;

	if (bcdev->num_thermal_levels <= 0)
		goto resched;

	max_level = bcdev->num_thermal_levels - 1;

	rc = battery_chg_get_temp_decic(bcdev, &temp_decic);
	if (rc < 0)
		goto resched;

	/* Emergency thermal protection: hardware lockup fallback */
	if (temp_decic >= 465) {
		rc = read_property_id(bcdev, pst_xm, XM_PROP_INPUT_SUSPEND);
		if (!rc && pst_xm->prop[XM_PROP_INPUT_SUSPEND] == 0) {
			pr_err("CRITICAL THERMAL LEVEL! Enabling INPUT_SUSPEND fallback\n");
			write_property_id(bcdev, pst_xm, XM_PROP_INPUT_SUSPEND, 1);
		}
	} else if (temp_decic <= 430) {
		rc = read_property_id(bcdev, pst_xm, XM_PROP_INPUT_SUSPEND);
		if (!rc && pst_xm->prop[XM_PROP_INPUT_SUSPEND] == 1) {
			pr_info("Temperature recovered. Disabling INPUT_SUSPEND fallback\n");
			write_property_id(bcdev, pst_xm, XM_PROP_INPUT_SUSPEND, 0);
		}
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
	schedule_delayed_work(&bcdev->chg_ctrl_limit_work,
				msecs_to_jiffies(CHG_CTRL_LIMIT_INTERVAL_MS));
}

#endif /* _QTI_BATTERY_CHARGER_THERMAL_POLICY_H */
