#include "linux/compiler.h"
#include "linux/cred.h"
#include "linux/jump_label.h"
#include "linux/printk.h"
#include "selinux/selinux.h"
#include <asm/syscall.h>
#include <linux/ptrace.h>
#include <linux/static_key.h>

#include "arch.h"
#include "klog.h" // IWYU pragma: keep
#include "hook/tp_marker.h"
#include "feature/sucompat.h"
#include "hook/setuid_hook.h"
#include "policy/app_profile.h"
#include "runtime/ksud.h"
#include "sulog/event.h"
#include "hook/syscall_hook.h"
#include "hook/syscall_event_bridge.h"
#include "feature/adb_root.h"
#include "feature/selinux_hide.h"

// - apply_kernelsu_rules() loads the SELinux policy rules the KSU/su domain
//   needs and, at its end, calls susfs_set_batch_sid() to populate
//   susfs_zygote_sid/susfs_ksu_sid/etc, which ksu_handle_setresuid() (and
//   thus all manager-app detection) depends on. This used to run from
//   ksu_handle_execveat_ksud() (runtime/ksud_integration.c), but that
//   function's only caller used an incompatible old-style signature and was
//   removed; reimplemented here using the same raw-regs string extraction
//   already used by ksu_handle_init_mark_tracker() below, since the original
//   helpers (check_argv/struct user_arg_ptr) are static to that other file.
static void ksu_handle_init_second_stage_tracker(const char __user **filename_user,
                                                  const char __user *const __user *argv_user)
{
    static const char system_bin_init[] = "/system/bin/init";
    static bool init_second_stage_executed = false;
    char path[32];
    unsigned long addr;
    const char __user *fn;
    const char __user *argv1_ptr;
    char argv1_buf[16];

    if (init_second_stage_executed || !filename_user || !argv_user)
        return;

    addr = untagged_addr((unsigned long)*filename_user);
    fn = (const char __user *)addr;
    if (strncpy_from_user(path, fn, sizeof(path)) < 0)
        return;
    path[sizeof(path) - 1] = '\0';

    if (memcmp(path, system_bin_init, sizeof(system_bin_init) - 1))
        return;

    if (get_user(argv1_ptr, argv_user + 1) || !argv1_ptr || IS_ERR(argv1_ptr))
        return;
    if (strncpy_from_user(argv1_buf, argv1_ptr, sizeof(argv1_buf)) <= 0)
        return;
    argv1_buf[sizeof(argv1_buf) - 1] = '\0';

    if (strcmp(argv1_buf, "second_stage"))
        return;

    pr_info("/system/bin/init second_stage executed\n");
    init_second_stage_executed = true;
    ksu_selinux_hide_handle_second_stage();
    apply_kernelsu_rules();
    cache_sid();
    setup_ksu_cred();
}

static int ksu_handle_init_mark_tracker(const char __user **filename_user)
{
    char path[64];
    unsigned long addr;
    const char __user *fn;
    long ret;

    if (unlikely(!filename_user))
        return 0;

    addr = untagged_addr((unsigned long)*filename_user);
    fn = (const char __user *)addr;
    ret = strncpy_from_user(path, fn, sizeof(path));
    if (ret < 0)
        return 0;

    path[sizeof(path) - 1] = '\0';
    if (unlikely(strcmp(path, KSUD_PATH) == 0)) {
        pr_info("hook_manager: escape to root for init executing ksud: %d\n", current->pid);
        escape_to_root_for_init();
    } else if (likely(strstr(path, "/app_process") == NULL && strstr(path, "/adbd") == NULL)) {
        pr_info("hook_manager: unmark %d exec %s\n", current->pid, path);
        ksu_clear_task_tracepoint_flag_if_needed(current);
    }

    return 0;
}

long __nocfi ksu_hook_newfstatat(int orig_nr, const struct pt_regs *regs)
{
    int *dfd;
    const char __user **filename_user;
    int *flags;

    if (!ksu_su_compat_enabled)
        return ksu_syscall_table[orig_nr](regs);

    dfd = (int *)&PT_REGS_PARM1(regs);
    filename_user = (const char __user **)&PT_REGS_PARM2(regs);
    flags = (int *)&PT_REGS_SYSCALL_PARM4(regs);
    ksu_handle_stat(dfd, filename_user, flags);

    return ksu_syscall_table[orig_nr](regs);
}

long __nocfi ksu_hook_faccessat(int orig_nr, const struct pt_regs *regs)
{
    int *dfd;
    const char __user **filename_user;
    int *mode;

    if (!ksu_su_compat_enabled)
        return ksu_syscall_table[orig_nr](regs);

    dfd = (int *)&PT_REGS_PARM1(regs);
    filename_user = (const char __user **)&PT_REGS_PARM2(regs);
    mode = (int *)&PT_REGS_PARM3(regs);
    ksu_handle_faccessat(dfd, filename_user, mode, NULL);

    return ksu_syscall_table[orig_nr](regs);
}

DEFINE_STATIC_KEY_TRUE(ksud_execve_key);

void ksu_stop_ksud_execve_hook()
{
    static_branch_disable(&ksud_execve_key);
}

long __nocfi ksu_hook_execve(int orig_nr, const struct pt_regs *regs)
{
    const char __user **filename_user = (const char __user **)&PT_REGS_PARM1(regs);
    const char __user *const __user *argv_user = (const char __user *const __user *)PT_REGS_PARM2(regs);
    void __user ***envp_user = (void __user ***)&PT_REGS_PARM3(regs);
    bool current_is_init = is_init(current_cred());
    struct ksu_sulog_pending_event *pending_root_execve = NULL;
    long ret;

    // ksud_execve_key / ksu_execve_hook_ksud removed: the zygote/app_process
    // post-fs-data bootstrap it used to also trigger is already reached via
    // the EVENT_POST_FS_DATA supercall reported by ksud's own boot scripts
    // (see supercall/dispatch.c do_report_event). The init-second-stage ->
    // apply_kernelsu_rules() path has no such alternative, so it is
    // reimplemented above as ksu_handle_init_second_stage_tracker() and
    // must run unconditionally (pid 1, so it would never be reached inside
    // the current->pid != 1 branch below).
    ksu_handle_init_second_stage_tracker(filename_user, argv_user);

    if (current->pid != 1 && current_is_init) {
        char adb_filename[128];
        long flen;

        ksu_handle_init_mark_tracker(filename_user);

        flen = strncpy_from_user(adb_filename, *filename_user, sizeof(adb_filename) - 1);
        if (flen > 0) {
            adb_filename[flen] = '\0';
            ret = ksu_adb_root_handle_execve(adb_filename, (void ***)envp_user);
            if (ret) {
                pr_err("adb root failed: %ld\n", ret);
            }
        }
    } else if (ksu_su_compat_enabled) {
        ret = ksu_handle_execve_sucompat(filename_user, orig_nr, regs);
        ksu_sulog_emit_pending(pending_root_execve, ret, GFP_KERNEL);
        return ret;
    }

    ret = ksu_syscall_table[orig_nr](regs);
    ksu_sulog_emit_pending(pending_root_execve, ret, GFP_KERNEL);
    return ret;
}

long __nocfi ksu_hook_setresuid(int orig_nr, const struct pt_regs *regs)
{
    long ret = ksu_syscall_table[orig_nr](regs);
    uid_t new_uid;

    if (ret < 0)
        return ret;

    new_uid = current_uid().val;
    ksu_handle_setresuid(new_uid, new_uid, new_uid);
    return ret;
}
