// SPDX-License-Identifier: GPL-2.0
/*
 * KernelSpace Profiles
 *
 * This Linux kernel module provides a framework for managing and switching between system profiles or modes
 * at the kernel level. Each profile represents a specific configuration of kernel features and settings
 * optimized for different use cases such as battery life, balanced performance, or maximum performance.
 *
 * The module supports various subsystems, including MSM DRM, MI DRM, and framebuffer (FB). It integrates
 * with these subsystems to receive notifications about screen state changes and adjust the active profile
 * accordingly.
 *
 * The module offers functions for setting the profile mode, overriding the mode temporarily, and retrieving
 * the active profile mode. Profiles can be dynamically switched based on system events, user requests, or
 * time-based rules.
 *
 * For more information and usage examples, refer to the README file at:
 * https://github.com/beakthoven/Kprofiles/blob/main/README.md
 *
 * Copyright (C) 2021-2025 Dakkshesh <dakkshesh5@gmail.com>
 * Version: 6.0.0
 * License: GPL-2.0
 */

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt

#include <linux/delay.h>
#include <linux/module.h>
#include <linux/moduleparam.h>
#include <linux/notifier.h>
#include <linux/kobject.h>
#include <linux/sysfs.h>
#include <linux/mutex.h>
#include <linux/compiler.h>
#include "version.h"

static BLOCKING_NOTIFIER_HEAD(kp_mode_notifier);
unsigned int KP_MODE_CHANGE = 0x80000000;
EXPORT_SYMBOL_GPL(KP_MODE_CHANGE);

static unsigned int kp_override_mode;
static bool kp_override;

static bool auto_kp __read_mostly = 0;
module_param(auto_kp, bool, 0664);
MODULE_PARM_DESC(auto_kp, "Enable/disable automatic kernel profile management");

static unsigned int kp_mode = CONFIG_KP_DEFAULT_MODE;

static struct kobject *kp_kobj;

DEFINE_MUTEX(kp_set_mode_rb_lock);

#ifdef CONFIG_KP_VERBOSE_DEBUG
#define kp_dbg(fmt, ...)	pr_info(fmt, ##__VA_ARGS__)
#else
#define kp_dbg(fmt, ...)
#endif

#define kp_err(fmt, ...)	pr_err(fmt, ##__VA_ARGS__)
#define kp_info(fmt, ...)	pr_info(fmt, ##__VA_ARGS__)

static void kp_trigger_mode_change_event(void);

static __always_inline int __kp_set_mode(unsigned int level)
{
	if (unlikely(level > 3))
		return -EINVAL;

	WRITE_ONCE(kp_mode, level);
	return 0;
}

/**
 * kp_set_mode_rollback - Change profile to a given mode for a specific duration
 * @level: The profile mode level to set (0-3)
 * @duration_ms: The duration to keep the profile mode in milliseconds
 *
 * This function changes the profile to the specified mode for a specific
 * duration during any in-kernel event, and then returns to the previously
 * active mode.
 *
 * Usage example: kp_set_mode_rollback(3, 55);
 */
void kp_set_mode_rollback(unsigned int level, unsigned int duration_ms)
{
	if (unlikely(level > 3)) {
		kp_err("Invalid mode requested, skipping mode change.\n");
		return;
	}

	mutex_lock(&kp_set_mode_rb_lock);

	WRITE_ONCE(kp_override_mode, level);
	WRITE_ONCE(kp_override, true);
	kp_trigger_mode_change_event();

	msleep(duration_ms);

	WRITE_ONCE(kp_override, false);
	kp_trigger_mode_change_event();

	mutex_unlock(&kp_set_mode_rb_lock);
}
EXPORT_SYMBOL_GPL(kp_set_mode_rollback);

/**
 * kp_set_mode - Change profile to a given mode
 * @level: The profile mode level to set (0-3)
 *
 * This function changes the profile to the specified mode during any
 * in-kernel event.
 *
 * Usage example: kp_set_mode(3);
 */
void kp_set_mode(unsigned int level)
{
	int ret = 0;

	mutex_lock(&kp_set_mode_rb_lock);

	ret = __kp_set_mode(level);
	if (ret) {
		kp_err("Invalid mode requested, skipping mode change.\n");
		mutex_unlock(&kp_set_mode_rb_lock);
		return;
	}

	kp_trigger_mode_change_event();

	mutex_unlock(&kp_set_mode_rb_lock);
}
EXPORT_SYMBOL_GPL(kp_set_mode);

/**
 * kp_active_mode - Get the currently active profile mode
 *
 * This function returns a number from 0 to 3 depending on the active profile mode.
 * The returned value can be used in conditions to disable/enable or tune kernel
 * features according to the profile mode.
 *
 * Return:
 * The currently active profile mode (0-3)
 *
 * Usage example:
 *
 * switch (kp_active_mode()) {
 * case 1:
 *     // Things to be done when battery profile is active
 *     break;
 * case 2:
 *     // Things to be done when balanced profile is active
 *     break;
 * case 3:
 *     // Things to be done when performance profile is active
 *     break;
 * default:
 *     // Things to be done when kprofiles is disabled
 *     break;
 * }
 */
int kp_active_mode(void)
{
	if (READ_ONCE(kp_override))
		return READ_ONCE(kp_override_mode);

	if (unlikely(READ_ONCE(kp_mode) > 3)) {
		WRITE_ONCE(kp_mode, 0);
		kp_trigger_mode_change_event();
		kp_err("Invalid value passed, falling back to level 0\n");
	}

	return READ_ONCE(kp_mode);
}
EXPORT_SYMBOL_GPL(kp_active_mode);

/**
 * kp_trigger_mode_change_event - Trigger a mode change event
 *
 * This function triggers a mode change event by calling the blocking notifier
 * chain for kp_mode_notifier. It informs all registered listeners about the
 * change in the profile mode.
 */
static __always_inline void kp_trigger_mode_change_event(void)
{
	unsigned int current_mode = kp_active_mode();

	blocking_notifier_call_chain(&kp_mode_notifier, KP_MODE_CHANGE,
				     (void *)(uintptr_t)current_mode);
}

/**
 * kp_notifier_register_client - Register a notifier client for profile mode changes
 * @nb: The notifier block to register
 *
 * This function registers a notifier client to receive notifications about profile mode changes.
 *
 * Return:
 * 0 on success, or an error code on failure.
 */
int kp_notifier_register_client(struct notifier_block *nb)
{
	return blocking_notifier_chain_register(&kp_mode_notifier, nb);
}
EXPORT_SYMBOL_GPL(kp_notifier_register_client);

/**
 * kp_notifier_unregister_client - Unregister a notifier client for profile mode changes
 * @nb: The notifier block to unregister
 *
 * This function unregisters a previously registered notifier client for profile mode changes.
 *
 * Return:
 * 0 on success, or an error code on failure.
 */
int kp_notifier_unregister_client(struct notifier_block *nb)
{
	return blocking_notifier_chain_unregister(&kp_mode_notifier, nb);
}
EXPORT_SYMBOL_GPL(kp_notifier_unregister_client);

static inline ssize_t kp_mode_show(struct kobject *kobj,
				   struct kobj_attribute *attr, char *buf)
{
	return sysfs_emit(buf, "%u\n", READ_ONCE(kp_mode));
}

static inline ssize_t kp_mode_store(struct kobject *kobj,
				    struct kobj_attribute *attr,
				    const char *buf, size_t count)
{
	unsigned int new_mode;
	int ret;

	ret = kstrtouint(buf, 10, &new_mode);
	if (ret)
		return ret;

	mutex_lock(&kp_set_mode_rb_lock);

	ret = __kp_set_mode(new_mode);
	if (ret) {
		kp_err("User changed mode is invalid, skipping mode change.\n");
		mutex_unlock(&kp_set_mode_rb_lock);
		return ret;
	}

	kp_trigger_mode_change_event();

	mutex_unlock(&kp_set_mode_rb_lock);

	return count;
}

static struct kobj_attribute kp_mode_attribute =
	__ATTR(kp_mode, 0664, kp_mode_show, kp_mode_store);

static struct attribute *kp_attrs[] = {
	&kp_mode_attribute.attr,
	NULL,
};

static struct attribute_group kp_attr_group = {
	.attrs = kp_attrs,
};

static int __init kp_init(void)
{
	int ret = 0;

	kp_kobj = kobject_create_and_add("kprofiles", kernel_kobj);
	if (!kp_kobj) {
		kp_err("Failed to create Kprofiles kobject\n");
		return -ENOMEM;
	}

	ret = sysfs_create_group(kp_kobj, &kp_attr_group);
	if (ret) {
		kp_err("Failed to create sysfs attributes for Kprofiles\n");
		kobject_put(kp_kobj);
		return ret;
	}

	kp_info("Kprofiles " KPROFILES_VERSION
		" loaded successfully. For further details, visit https://github.com/beakthoven/Kprofiles/blob/main/README.md\n");
	kp_info("Copyright (C) 2021-2025 Dakkshesh <dakkshesh5@gmail.com>.\n");

	return ret;
}
module_init(kp_init);

static void __exit kp_exit(void)
{
	sysfs_remove_group(kp_kobj, &kp_attr_group);
	kobject_put(kp_kobj);
}
module_exit(kp_exit);

MODULE_LICENSE("GPL v2");
MODULE_DESCRIPTION("KernelSpace Profiles");
MODULE_AUTHOR("Dakkshesh <dakkshesh5@gmail.com>");
MODULE_VERSION(KPROFILES_VERSION);
