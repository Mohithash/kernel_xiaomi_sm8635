/* SPDX-License-Identifier: GPL-2.0-only */
/*
 *  Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
 */

#ifndef __SI_CORE_ADCI_H__
#define __SI_CORE_ADCI_H__

#if defined(CONFIG_QCOM_SI_CORE_ADCI)
void adci_start(void);
int adci_shutdown(void);
#else
/**
 * adci_start - Stub function when ADCI is disabled.
 *
 * This function performs no operation and is inlined
 * to eliminate call overhead.
 */
static inline void adci_start(void)
{
	/* No operation */
}

/**
 * adci_shutdown - Stub function when ADCI is disabled.
 *
 * This function performs no operation and returns 0 to
 * indicate success
 *
 * Returns: 0 for success.
 */
static inline int adci_shutdown(void)
{
	return 0;
}
#endif /* CONFIG_QCOM_SI_CORE_ADCI */


#endif /* __SI_CORE_ADCI_H__ */
