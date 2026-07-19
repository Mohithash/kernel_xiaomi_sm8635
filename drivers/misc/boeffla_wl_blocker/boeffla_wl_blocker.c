// SPDX-License-Identifier: GPL-2.0
/*
 * Boeffla wakelock blocker — Theettam / peridot (SM8635)
 *
 * Hooks wakeup_source activation via vendor hook if available, else
 * provides sysfs list consumed by a thin binder in kernel/power/wakeup.c
 * (see theettam/patches/0003-wakeup-boeffla-hook.patch).
 *
 * Design: keep KMI stable — only adds a miscdevice + exported helper.
 */

#include <linux/module.h>
#include <linux/kobject.h>
#include <linux/sysfs.h>
#include <linux/string.h>
#include <linux/miscdevice.h>
#include <linux/slab.h>
#include <linux/spinlock.h>
#include "boeffla_wl_blocker.h"

static char *list1;
static char *list2;
static size_t list1_len;
static size_t list2_len;
static DEFINE_SPINLOCK(list_lock);

static bool list_match(const char *ws_name, const char *list, size_t len)
{
	const char *p, *end, *semi;
	size_t nlen, wlen;

	if (!ws_name || !list || !len)
		return false;

	wlen = strlen(ws_name);
	p = list;
	end = list + len;
	while (p < end) {
		while (p < end && (*p == ';' || *p == ' '))
			p++;
		if (p >= end)
			break;
		semi = memchr(p, ';', end - p);
		nlen = semi ? (size_t)(semi - p) : (size_t)(end - p);
		while (nlen && p[nlen - 1] == ' ')
			nlen--;
		if (nlen == wlen && !strncmp(p, ws_name, wlen))
			return true;
		p = semi ? semi + 1 : end;
	}
	return false;
}

/**
 * theettam_wl_should_block - return true if wakelock name is blocked
 * @name: wakeup_source name
 *
 * Called from patched wakeup_source_activate path.
 */
bool theettam_wl_should_block(const char *name)
{
	unsigned long flags;
	bool block = false;

	if (!name || !*name)
		return false;

	spin_lock_irqsave(&list_lock, flags);
	if (list1 && list_match(name, list1, list1_len))
		block = true;
	else if (list2 && list_match(name, list2, list2_len))
		block = true;
	spin_unlock_irqrestore(&list_lock, flags);
	return block;
}
EXPORT_SYMBOL_GPL(theettam_wl_should_block);

static ssize_t version_show(struct device *dev,
			    struct device_attribute *attr, char *buf)
{
	return sysfs_emit(buf, "%s\n", BOEFFLA_WL_BLOCKER_VERSION);
}
static DEVICE_ATTR_RO(version);

static ssize_t wakelock_blocker_show(struct device *dev,
				     struct device_attribute *attr, char *buf)
{
	unsigned long flags;
	ssize_t ret;

	spin_lock_irqsave(&list_lock, flags);
	ret = sysfs_emit(buf, "%s\n", list1 ? list1 : "");
	spin_unlock_irqrestore(&list_lock, flags);
	return ret;
}

static ssize_t wakelock_blocker_store(struct device *dev,
				      struct device_attribute *attr,
				      const char *buf, size_t count)
{
	char *new;
	unsigned long flags;

	new = kstrndup(buf, count, GFP_KERNEL);
	if (!new)
		return -ENOMEM;
	/* strip trailing newline */
	if (count && new[count - 1] == '\n')
		new[count - 1] = '\0';

	spin_lock_irqsave(&list_lock, flags);
	kfree(list1);
	list1 = new;
	list1_len = strlen(new);
	spin_unlock_irqrestore(&list_lock, flags);
	return count;
}
static DEVICE_ATTR_RW(wakelock_blocker);

static ssize_t wakelock_blocker_default_show(struct device *dev,
					     struct device_attribute *attr,
					     char *buf)
{
	return sysfs_emit(buf, "%s\n", BOEFFLA_WLBLOCKER_DEFAULTS);
}
static DEVICE_ATTR_RO(wakelock_blocker_default);

static struct attribute *boeffla_attrs[] = {
	&dev_attr_version.attr,
	&dev_attr_wakelock_blocker.attr,
	&dev_attr_wakelock_blocker_default.attr,
	NULL,
};
ATTRIBUTE_GROUPS(boeffla);

static struct miscdevice boeffla_misc = {
	.minor = MISC_DYNAMIC_MINOR,
	.name  = "boeffla_wakelock_blocker",
	.groups = boeffla_groups,
};

static int __init boeffla_wl_blocker_init(void)
{
	int ret;

	list1 = kstrdup(BOEFFLA_WLBLOCKER_DEFAULTS, GFP_KERNEL);
	if (!list1)
		return -ENOMEM;
	list1_len = strlen(list1);

	list2 = NULL;
	list2_len = 0;

	ret = misc_register(&boeffla_misc);
	if (ret) {
		kfree(list1);
		list1 = NULL;
		return ret;
	}

	pr_info("boeffla_wl_blocker: Theettam %s loaded (qcom_rx_wakelock blocked by default)\n",
		BOEFFLA_WL_BLOCKER_VERSION);
	return 0;
}

static void __exit boeffla_wl_blocker_exit(void)
{
	unsigned long flags;

	misc_deregister(&boeffla_misc);
	spin_lock_irqsave(&list_lock, flags);
	kfree(list1);
	kfree(list2);
	list1 = list2 = NULL;
	spin_unlock_irqrestore(&list_lock, flags);
}

module_init(boeffla_wl_blocker_init);
module_exit(boeffla_wl_blocker_exit);
MODULE_LICENSE("GPL");
MODULE_AUTHOR("Theettam Kernel");
MODULE_DESCRIPTION("Boeffla-style wakelock blocker for SM8635 / VoltageOS");
