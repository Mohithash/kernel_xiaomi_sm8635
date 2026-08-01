#!/bin/bash
# fix-lsm-hook-lto.sh — Fix selinux_hide hook binding under GKI ThinLTO
#
# Problem: ksu_lsm_hook() resolves a target function address from kallsyms
# and compares it to every function pointer in security_hook_heads. Under
# ThinLTO (GKI), the LTO linker can alias or rename static symbols (e.g.
# selinux_setprocattr -> selinux_setprocattr.llvm.XXXXXXXX), causing the
# resolved address to differ from the pointer in the hook table -> ENOENT.
#
# Fix: when the address-based walk finds no match, fall back to matching by
# symbol name. Go directly to the correct hlist_head via head_offset, resolve
# each entry's function pointer back to its kallsyms name, and prefix-match
# against target_name (tolerating LTO .llvm.* suffixes).
#
# Usage: bash scripts/fix-lsm-hook-lto.sh <path-to-lsm_hook.c>
#   e.g.: bash scripts/fix-lsm-hook-lto.sh KernelSU/kernel/hook/lsm_hook.c

set -euo pipefail

F="${1:?Usage: $0 <path-to-lsm_hook.c>}"
[ -f "$F" ] || { echo "::error::$F not found"; exit 1; }

if grep -q 'LTO fallback' "$F"; then
    echo "[i] LTO fallback already present in $F — skipping"
    exit 0
fi

ANCHOR='target %s not found in head %s'
if ! grep -q "$ANCHOR" "$F"; then
    echo "::error::anchor text not found in $F — upstream may have changed"
    exit 1
fi

python3 - "$F" <<'PYEOF'
import sys

f = sys.argv[1]
src = open(f).read()

old = """\
    if (!selected_entry) {
        pr_err("lsm_hook: target %s not found in head %s\\n", target_name, hook->head_name ?: "unknown");
        ret = -ENOENT;
        goto out_unlock;
    }"""

fallback = """\
    /* LTO fallback: address-based walk found no match -- ThinLTO may alias
     * or rename the symbol. Go directly to the target hlist_head and match
     * by resolving each entry's function pointer back to its symbol name. */
    if (!selected_entry && !hook->offset) {
        struct hlist_head *target_head =
            (struct hlist_head *)(heads_addr + hook->head_offset);
        char sym_buf[KSYM_NAME_LEN];
        size_t tname_len = strlen(hook->target_name);
        hlist_for_each_entry(entry, target_head, list) {
            void **slot = (void **)((char *)entry + hook->hook_offset);
            void *current_origin = READ_ONCE(*slot);
            int j;
            for (j = 0; j < ksu_lsm_hook_count; j++) {
                if (ksu_lsm_hook_entries[j].hook->replacement == current_origin) {
                    current_origin = ksu_lsm_hook_entries[j].hook->original;
                    break;
                }
            }
            sprint_symbol_no_offset(sym_buf, (unsigned long)current_origin);
            if (strncmp(sym_buf, hook->target_name, tname_len) == 0 &&
                (sym_buf[tname_len] == '\\0' || sym_buf[tname_len] == '.')) {
                selected_entry = entry;
                selected_slot = slot;
                selected_origin = current_origin;
                pr_info("lsm_hook: LTO fallback matched %s (sym=%s) in head %s\\n",
                        hook->target_name, sym_buf, hook->head_name ?: "unknown");
                break;
            }
        }
    }

    if (!selected_entry) {
        pr_err("lsm_hook: target %s not found in head %s\\n", target_name, hook->head_name ?: "unknown");
        ret = -ENOENT;
        goto out_unlock;
    }"""

if old not in src:
    print("::error::anchor block not found in " + f, file=sys.stderr)
    sys.exit(1)

count = src.count(old)
if count != 1:
    print(f"::error::anchor block appears {count} times (expected 1)", file=sys.stderr)
    sys.exit(1)

patched = src.replace(old, fallback, 1)
open(f, 'w').write(patched)
print(f"[+] LTO fallback patched into {f}")
PYEOF
