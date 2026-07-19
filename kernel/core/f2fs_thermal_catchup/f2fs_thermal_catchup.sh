#!/usr/bin/env bash

# ======================================================
# 🩹 CORE — f2fs / thermal stable catch-up (v6.1.175 → v6.1.177)
# ======================================================
# Lote 2: 8 real upstream fixes cherry-picked from linux-6.1.y (gregkh/linux),
# same methodology as mm_stable_catchup (lote 1) — verified with a real
# `git apply --check` against this tree, hand-adapted where the raw diff
# didn't apply as-is.
#
# Included (see lote2_f2fs_thermal.patch):
#   1. fs/f2fs/{node,segment,super}.c — kfree() instead of kvfree() where
#      the allocation is never vmalloc'd (prerequisite for #2)
#   2. fs/f2fs/{f2fs.h,segment.c,super.c} — conditional sanity check on
#      dcc->discard_cmd_cnt (adapted: this tree's f2fs_remount() calls
#      f2fs_issue_discard_timeout() unconditionally, no pre-existing
#      atomic_read guard like upstream's context — ported the added
#      `need_check` parameter directly instead)
#   3. fs/f2fs/data.c — fix UAF in f2fs_write_end_io() (unmount vs
#      checkpoint I/O completion race — real KASAN-caught bug)
#   4. fs/f2fs/inline.c — fix fiemap() address mapping on un-persisted
#      inline inodes
#   5. fs/f2fs/inode.c — only trust the compress-cache inode number when
#      compress_cache is actually mounted (CONFIG_F2FS_FS_COMPRESSION=y
#      confirmed active in this tree's gki_defconfig)
#   6. fs/f2fs/file.c — round fallocate's start offset down to a section
#      boundary for pinned files (adapted: same target function and pin
#      block confirmed present, applied against the tree's actual
#      f2fs_lock_context-based structure)
#   7. fs/f2fs/acl.c — validate ACL entry size in f2fs_acl_from_disk()
#      (real KASAN slab-out-of-bounds on malformed ACL xattr,
#      CONFIG_F2FS_FS_POSIX_ACL=y confirmed active via luminaire.fragment)
#   8. drivers/thermal/thermal_core.c — fix governor leak on failed zone
#      registration + UAF on concurrent governor swap via sysfs without
#      holding the zone lock
#
# Skipped from this batch on purpose (not bundled here):
#   - arm64 TLBI XZR + ARM64_WORKAROUND_REPEAT_TLBI optimization: this
#     tree implements the repeat-TLBI erratum workaround with a different
#     runtime-check mechanism than upstream's ALTERNATIVE-in-macro
#     approach, and the workaround doesn't appear at all in kvm/hyp/ here
#     — hand-porting into hypervisor TLB code without a confirmed mapping
#     is a real correctness risk, skipped rather than guessed.
#   - arm64 TLBI errata CVE-2025-10263 (cpu_errata.c): explicitly a
#     security-for-overhead tradeoff per its own commit message, excluded
#     per standing instruction to leave those out of this catch-up.

PATCH_FILE="$(dirname "${BASH_SOURCE[0]}")/lote2_f2fs_thermal.patch"

log "🩹 Applying f2fs/thermal stable catch-up (lote 2)..."
cd "${KERNEL_SRC}"

if git apply --check --reverse "$PATCH_FILE" > /dev/null 2>&1; then
    log "f2fs/thermal stable catch-up: already applied, skipping."
elif git apply --check "$PATCH_FILE" > /dev/null 2>&1; then
    git apply "$PATCH_FILE" || error "f2fs/thermal stable catch-up: apply failed!"
    log "f2fs/thermal stable catch-up: applied (8 fixes) ✅"
else
    error "f2fs/thermal stable catch-up: does not apply cleanly — kernel source may have changed since this was written, needs re-verification!"
fi

cd "${ROOT_DIR}"

log "f2fs/thermal stable catch-up integrated ✅"
