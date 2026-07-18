#!/usr/bin/env bash
# Enable CONFIG_SYSVIPC on a GKI kernel without breaking the frozen KMI.
#
# SYSVIPC normally inserts sysvsem/sysvshm into the middle of task_struct, shifting
# every field after them. Prebuilt vendor modules are linked against the original
# layout, so that is an immediate bootloop -- this is exactly the KABI break class
# that makes mainline LTS unusable on GKI.
#
# The fix (originally by nullptr-t-oss for Droidspaces) relocates both fields into
# task_struct's ANDROID_KABI reserve slots, which exist for precisely this purpose:
#
#     struct sysv_sem { struct sem_undo_list *undo_list; }   ->  8 bytes  -> slot 6
#     struct sysv_shm { struct list_head shm_clist; }        -> 16 bytes  -> slots 7+8
#
# One _ANDROID_KABI_RESERVE(n) is a u64. __ANDROID_KABI_CHECK_SIZE_ALIGN turns the
# fit into a compile-time _Static_assert, so bad arithmetic fails the build rather
# than silently corrupting task_struct.
#
# Upstream ships this as a patch, but its context assumes ANDROID_KABI_RESERVE(3) is
# free. This tree USES slot 3 (user_dumpable), so the patch rejects. Anchored edits
# instead of patch(1): if an anchor moves, this aborts loudly rather than fuzzing a
# hunk into the wrong struct.
#
# Usage: integrate.sh [kernel_root]
set -euo pipefail
KROOT="${1:-$PWD}"
SCHED="$KROOT/include/linux/sched.h"
[ -f "$SCHED" ] || { echo "[!] no $SCHED"; exit 1; }

echo "[*] droidspaces: relocating SYSVIPC fields into task_struct KABI reserve"

python3 - "$SCHED" <<'PY'
import sys
f = sys.argv[1]
code = open(f, encoding='utf-8').read()

if 'ANDROID_KABI_USE(6, struct sysv_sem sysvsem)' in code:
    print("  [=] already applied")
    raise SystemExit(0)

# 1) Drop the fields from their layout-shifting position. Keep the #ifdef so the
#    file still reads as upstream's, and leave the originals visible as comments.
old_pos = ("#ifdef CONFIG_SYSVIPC\n"
           "\tstruct sysv_sem\t\t\tsysvsem;\n"
           "\tstruct sysv_shm\t\t\tsysvshm;\n"
           "#endif\n")
new_pos = ("#ifdef CONFIG_SYSVIPC\n"
           "\t/* Moved to ANDROID_KABI_USE(6)/(7,8) below: declaring these here would\n"
           "\t * shift every subsequent task_struct offset and break prebuilt vendor\n"
           "\t * modules. See scripts/droidspaces/integrate.sh. */\n"
           "\t/* struct sysv_sem\t\tsysvsem; */\n"
           "\t/* struct sysv_shm\t\tsysvshm; */\n"
           "#endif\n")
assert old_pos in code, "sysvsem/sysvshm anchor not found in task_struct"
code = code.replace(old_pos, new_pos, 1)

# 2) Re-declare them in the reserve slots. Slots 1-3 are already USEd by this tree
#    (saved_state, dmabuf_info, user_dumpable); 4 and 5 stay free for the vendor.
old_res = ("\tANDROID_KABI_RESERVE(6);\n"
           "\tANDROID_KABI_RESERVE(7);\n"
           "\tANDROID_KABI_RESERVE(8);\n")
new_res = ("#ifdef CONFIG_SYSVIPC\n"
           "\tANDROID_KABI_USE(6, struct sysv_sem sysvsem);\n"
           "\t_ANDROID_KABI_REPLACE(ANDROID_KABI_RESERVE(7); ANDROID_KABI_RESERVE(8),\n"
           "\t\t\t      struct sysv_shm sysvshm);\n"
           "#else\n"
           "\tANDROID_KABI_RESERVE(6);\n"
           "\tANDROID_KABI_RESERVE(7);\n"
           "\tANDROID_KABI_RESERVE(8);\n"
           "#endif\n")
assert old_res in code, "ANDROID_KABI_RESERVE(6..8) anchor not found"
assert code.count(old_res) == 1, "RESERVE(6..8) is ambiguous -- refusing to guess"
code = code.replace(old_res, new_res, 1)

open(f, 'w', encoding='utf-8').write(code)
print("  [+] sysvsem -> ANDROID_KABI_USE(6); sysvshm -> slots 7+8")
PY

echo "[*] droidspaces: kernel side done"
