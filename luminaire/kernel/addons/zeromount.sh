#!/usr/bin/env bash

# ======================================================
# 📦 ADDON — ZeroMount (VFS path redirection engine)
# ======================================================
# Repo: https://github.com/Enginex0/zeromount
# Patch source: https://github.com/Enginex0/Super-Builders
# Note: self-contained patch (creates fs/zeromount.c,
#       include/linux/zeromount.h, Kconfig + Makefile wiring).
#       Directory-listing injection hunks anchor on
#       CONFIG_KSU_SUSFS_SUS_PATH context — best paired with
#       SuSFS. Falls back gracefully (warn+continue) without it.

ZEROMOUNT_PATCH_URL="https://raw.githubusercontent.com/Enginex0/Super-Builders/main/android14-6.1/ReSukiSU/patches/60_zeromount-android14-6.1.patch"
ZEROMOUNT_PATCH="/tmp/60_zeromount-android14-6.1.patch"

log "Downloading ZeroMount kernel patch..."
retry 3 run_quiet curl -fSL "$ZEROMOUNT_PATCH_URL" -o "$ZEROMOUNT_PATCH" \
    || { warn "ZeroMount patch download failed — skipping"; return 0; }

log "Applying ZeroMount kernel patch..."
if patch -p1 --fuzz=3 --dry-run --reverse -d "$KERNEL_SRC" < "$ZEROMOUNT_PATCH" > /dev/null 2>&1; then
    log "ZeroMount patch already applied, skipping."
else
    patch -p1 --fuzz=3 --forward -d "$KERNEL_SRC" < "$ZEROMOUNT_PATCH" \
        && log "ZeroMount patch applied ✅" \
        || warn "ZeroMount patch: some hunks failed — continuing (dir-listing injection may be degraded without SuSFS)"
fi

rm -f "$ZEROMOUNT_PATCH"

log "Fixing namei.c scope issues (zeromount blocks in wrong positions)..."
python3 - "${KERNEL_SRC}/fs/namei.c" << 'PYEOF'
import sys, re

with open(sys.argv[1]) as f:
    content = f.read()

# Fix 1: Move #include <linux/zeromount.h> from inside a function to top-level
# The patch places it inside posix_acl_check() which is invalid C
INCLUDE_INSIDE = (
    '#ifdef CONFIG_ZEROMOUNT\n'
    '#include <linux/zeromount.h>\n'
    '#endif\n'
)

if INCLUDE_INSIDE in content:
    count = content.count(INCLUDE_INSIDE)
    # Remove ALL occurrences
    content = content.replace(INCLUDE_INSIDE, '')
    # Insert once after last #include in proper include section (before line 60)
    lines = content.split('\n')
    insert_after = 0
    for i, line in enumerate(lines[:60]):
        if line.startswith('#include'):
            insert_after = i
    lines.insert(insert_after + 1,
                 '#ifdef CONFIG_ZEROMOUNT\n'
                 '#include <linux/zeromount.h>\n'
                 '#endif')
    content = '\n'.join(lines)
    print(f"namei.c: removed {count} misplaced include(s), re-inserted at line {insert_after + 2}.")
else:
    print("namei.c: include already in correct position or not found.")

# Fix 2: Remove misplaced zeromount function call blocks
ZM_BLOCK = (
    '\n#ifdef CONFIG_ZEROMOUNT\n'
    '\tif (zeromount_is_injected_file(inode)) {\n'
    '\t\tif (mask & MAY_WRITE)\n'
    '\t\t\treturn -EACCES;\n'
    '\t\treturn 0;\n'
    '\t}\n'
    '\n'
    '\tif (S_ISDIR(inode->i_mode) && zeromount_is_traversal_allowed(inode, mask)) {\n'
    '\t\treturn 0;\n'
    '\t}\n'
    '#endif\n'
)
count = content.count(ZM_BLOCK)
if count:
    content = content.replace(ZM_BLOCK, '')
    print(f"namei.c: removed {count} misplaced zeromount call block(s).")

with open(sys.argv[1], 'w') as f:
    f.write(content)
PYEOF
log "namei.c fixed ✅"

log "Fixing task_mmu.c scope issue (zeromount call outside inode scope)..."
python3 - "${KERNEL_SRC}/fs/proc/task_mmu.c" << 'PYEOF'
import sys

with open(sys.argv[1]) as f:
    content = f.read()

# Case A: with SuSFS — zeromount call landed after SUS_KSTAT block
# but still inside if(file){} scope
broken_susfs = (
    '#ifdef CONFIG_KSU_SUSFS_SUS_KSTAT\n'
    '\t\tsusfs_sus_kstat_spoof_show_map_vma(inode, &dev, &ino);\n'
    '#endif // #ifdef CONFIG_KSU_SUSFS_SUS_KSTAT\n'
    '\t}\n'
    '\n'
    '#ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT\n'
    '#ifdef CONFIG_ZEROMOUNT\n'
    '\t\tzeromount_spoof_mmap_metadata(inode, &dev, &ino);\n'
    '#endif\n'
    'orig_flow:\n'
    '#endif // #ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT'
)
fixed_susfs = (
    '#ifdef CONFIG_KSU_SUSFS_SUS_KSTAT\n'
    '\t\tsusfs_sus_kstat_spoof_show_map_vma(inode, &dev, &ino);\n'
    '#endif // #ifdef CONFIG_KSU_SUSFS_SUS_KSTAT\n'
    '#ifdef CONFIG_ZEROMOUNT\n'
    '\t\tzeromount_spoof_mmap_metadata(inode, &dev, &ino);\n'
    '#endif\n'
    '\t}\n'
    '\n'
    '#ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT\n'
    'orig_flow:\n'
    '#endif // #ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT'
)

# Case B: without SuSFS — zeromount call landed in wrong scope entirely
# (inside if(!mm) block instead of if(file) block)
broken_vanilla = (
    '\t\tif (!mm) {\n'
    '\t\t\tname = "[vdso]";\n'
    '\t\t\tgoto done;\n'
    '\t\t}\n'
    '\n'
    '#ifdef CONFIG_ZEROMOUNT\n'
    '\t\tzeromount_spoof_mmap_metadata(inode, &dev, &ino);\n'
    '#endif\n'
    '\t\tif (vma->vm_start <= mm->brk &&'
)
fixed_vanilla = (
    '\t\tif (!mm) {\n'
    '\t\t\tname = "[vdso]";\n'
    '\t\t\tgoto done;\n'
    '\t\t}\n'
    '\n'
    '\t\tif (vma->vm_start <= mm->brk &&'
)

if broken_susfs in content:
    content = content.replace(broken_susfs, fixed_susfs)
    print("task_mmu.c scope fix applied (with-SuSFS case).")
elif broken_vanilla in content:
    # For vanilla: just remove the misplaced call entirely from wrong scope.
    # zeromount's show_map_vma hook in the patch already handles this
    # correctly via the other hook points (d_path.c, stat.c).
    content = content.replace(broken_vanilla,
        '\t\tif (!mm) {\n'
        '\t\t\tname = "[vdso]";\n'
        '\t\t\tgoto done;\n'
        '\t\t}\n'
        '\n'
        '\t\tif (vma->vm_start <= mm->brk &&'
    )
    print("task_mmu.c scope fix applied (vanilla/no-SuSFS case).")
elif "zeromount_spoof_mmap_metadata" not in content:
    print("zeromount call not found, skipping.")
else:
    print("Pattern already fixed or different, skipping.")

with open(sys.argv[1], 'w') as f:
    f.write(content)
PYEOF
log "task_mmu.c fixed ✅"

log "ZeroMount integrated ✅"
