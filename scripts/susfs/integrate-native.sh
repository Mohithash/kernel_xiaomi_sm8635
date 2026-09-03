#!/usr/bin/env bash
# Native-susfs driver integration (ReSukiSU): the driver already implements all the
# susfs driver-side symbols (ksu_handle_sys_reboot, susfs_is_current_ksu_domain,
# susfs_ksu_sid, the inline ksu_handle_* hooks, selinux_hide, etc.). So we only add
# the fs-side (susfs4ksu 50_ patch) — NO driver edits, NO hunk stripping, NO shims
# (those would DUPLICATE the driver's native symbols and fail to link).
set -euo pipefail

S4K_DIR="${1:?susfs4ksu dir}"
KROOT="${2:?kernel root}"
P50="$S4K_DIR/kernel_patches/50_add_susfs_in_gki-android14-6.1.patch"

echo "[*] === NATIVE susfs integration (fs-side only) ==="

# fs-side sources + headers
cp -v "$S4K_DIR"/kernel_patches/fs/*.c "$KROOT/fs/"
cp -v "$S4K_DIR"/kernel_patches/include/linux/*.h "$KROOT/include/linux/"

cd "$KROOT"
# apply the FULL fs-side patch (namespace.c top-decl hunk expected to reject -> fixup below)
patch -p1 < "$P50" || true
# The ONLY reject we accept is namespace.c's top-of-file decl hunk (the fixup below
# re-creates it). Any other reject -- in namespace.c or elsewhere -- means the base
# moved under the susfs patch; that must fail loudly, not be deleted and compiled.
if [ -f fs/namespace.c.rej ]; then
  _hunks=$(grep -c '^@@' fs/namespace.c.rej || true)
  if [ "$_hunks" != 1 ] || ! grep -q '^@@ -32,10 ' fs/namespace.c.rej; then
    echo "[!] fs/namespace.c: unexpected reject(s) -- not just the known top-decl hunk:"; cat fs/namespace.c.rej; exit 1
  fi
fi
_other=$(find . -path ./out -prune -o -name '*.rej' -print | grep -v '^./fs/namespace.c.rej$' || true)
if [ -n "$_other" ]; then echo "[!] rejects outside namespace.c:"; for r in $_other; do echo "== $r =="; cat "$r"; done; exit 1; fi

# namespace.c susfs decl block (the one expected reject; idempotent)
python3 - <<'PY'
f="fs/namespace.c"; s=open(f).read()
assert "#include <linux/mnt_idmapping.h>\n" in s, "namespace.c anchor <linux/mnt_idmapping.h> missing"
assert '#include "internal.h"\n' in s, 'namespace.c anchor "internal.h" missing'
inc="#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n#include <linux/susfs_def.h>\n#endif\n"
ext=("#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n"
     "extern bool susfs_is_current_ksu_domain(void);\n"
     "extern struct static_key_true susfs_is_sdcard_android_data_not_decrypted;\n"
     "#define CL_COPY_MNT_NS BIT(25)\n#endif\n")
if "susfs_def.h" not in s:
    s=s.replace("#include <linux/mnt_idmapping.h>\n","#include <linux/mnt_idmapping.h>\n"+inc,1)
if "extern bool susfs_is_current_ksu_domain" not in s:
    s=s.replace('#include "internal.h"\n','#include "internal.h"\n'+ext,1)
open(f,"w").write(s)
print("  [+] namespace.c susfs decls applied")
PY
rm -f fs/namespace.c.rej fs/namespace.c.orig   # only the known hunk-1 reject survives the gate above

# vendor modules must still load after susfs CRC changes
for f in android/abi_gki_protected_exports_aarch64 android/abi_gki_protected_exports_x86_64; do
  [ -f "$f" ] && : > "$f" && echo "  [+] emptied $f"
done

REJ="$(find . -name '*.rej' 2>/dev/null || true)"
if [ -n "$REJ" ]; then echo "[!] REJECTS:"; for r in $REJ; do echo "== $r =="; cat "$r"; done; exit 1; fi
echo "[*] native susfs integration complete, no rejects"
