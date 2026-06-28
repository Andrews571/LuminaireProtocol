#!/usr/bin/env bash

# ======================================================
# 🧬 SuSFS — shared apply logic (any KSU fork, android14-6.1-lts)
# ======================================================

# SuSFS compatibility guard
# SukiSU-Ultra uses syscall_hook_manager with restricted symbol
# visibility — incompatible with susfs4ksu adapter patches without
# pinning to an older commit. Skip early to avoid wasting build time.
SUSFS_INCOMPATIBLE_FORKS=("SUKISU")
for _fork in "${SUSFS_INCOMPATIBLE_FORKS[@]}"; do
    if [ "$ROOT_SOLUTION" = "$_fork" ]; then
        warn "SuSFS is not supported for ${ROOT_SOLUTION} (incompatible hook architecture — see wishlist)"
        warn "Building ${ROOT_SOLUTION} WITHOUT SuSFS."
        return 0
    fi
done

KSU_DIR="${KSU_DIR:-${KERNEL_SRC}/KernelSU}"
SUSFS_BRANCH="gki-android14-6.1"
SUSFS_REPO="https://gitlab.com/simonpunk/susfs4ksu.git"
SUSFS_DIR="/tmp/susfs4ksu"
PATCHER_DIR="${LUMINAIRE_PATCH_DIR}/kernel/android14-6.1-lts/ksu/susfs"

log "Cloning SuSFS (${SUSFS_BRANCH})..."
[ -d "$SUSFS_DIR" ] && rm -rf "$SUSFS_DIR"
git config --global http.connectTimeout 30
git config --global http.lowSpeedLimit 1000
git config --global http.lowSpeedTime 30
retry 3 run_quiet git clone -q --depth=1 -b "$SUSFS_BRANCH" "$SUSFS_REPO" "$SUSFS_DIR" \
    || error "SuSFS clone failed after 3 attempts!"

log "Copying SuSFS source files..."
cp "${SUSFS_DIR}/kernel_patches/fs/susfs.c"                  "${KERNEL_SRC}/fs/susfs.c"
cp "${SUSFS_DIR}/kernel_patches/include/linux/susfs.h"       "${KERNEL_SRC}/include/linux/susfs.h"
cp "${SUSFS_DIR}/kernel_patches/include/linux/susfs_def.h"   "${KERNEL_SRC}/include/linux/susfs_def.h"
log "SuSFS source files copied ✅"

log "Applying SuSFS kernel patch..."
KERNEL_PATCH="${SUSFS_DIR}/kernel_patches/50_add_susfs_in_gki-android14-6.1.patch"
[ -f "$KERNEL_PATCH" ] || { warn "SuSFS kernel patch not found — skipping"; return 0; }
if patch -p1 --fuzz=3 --dry-run --reverse -d "$KERNEL_SRC" < "$KERNEL_PATCH" > /dev/null 2>&1; then
    log "SuSFS kernel patch already applied, skipping."
else
    # Pre-patch: sublevel >= 157 adds #include <trace/hooks/blk.h> to namespace.c
    # which shifts context and causes hunk #1 to fail. Remove it temporarily so
    # the patch can match, then restore after.
    if [ "${SUBLEVEL:-0}" -ge 157 ]; then
        log "Pre-patch: removing blk.h from namespace.c for context match (sublevel ${SUBLEVEL})..."
        sed -i '/^#include <trace\/hooks\/blk\.h>$/d' "${KERNEL_SRC}/fs/namespace.c"
    fi

    patch -p1 --fuzz=3 --forward -d "$KERNEL_SRC" < "$KERNEL_PATCH" \
        && log "SuSFS kernel patch applied ✅" \
        || warn "SuSFS kernel patch: some hunks failed — continuing"

    # Post-patch: restore blk.h if it was removed and patch didn't re-add it
    if [ "${SUBLEVEL:-0}" -ge 157 ] && ! grep -qF '#include <trace/hooks/blk.h>' "${KERNEL_SRC}/fs/namespace.c"; then
        log "Post-patch: restoring blk.h to namespace.c..."
        sed -i '/^#include "internal\.h"$/a #include <trace\/hooks\/blk.h>' "${KERNEL_SRC}/fs/namespace.c"
    fi

    # Cleanup any leftover .rej files
    find "$KERNEL_SRC" -name "*.rej" -delete 2>/dev/null || true
fi

log "Fixing namespace.c susfs declarations (safety fallback)..."
python3 "${PATCHER_DIR}/fix_namespace.py" "${KERNEL_SRC}/fs/namespace.c" \
    || error "SuSFS: namespace.c fix failed!"
log "namespace.c fixed ✅"

rm -rf "$SUSFS_DIR"

log "Ensuring KSU_SUSFS Kconfig declarations exist..."
KSU_KCONFIG="${KSU_DIR}/kernel/Kconfig"
if [ -f "$KSU_KCONFIG" ] && grep -q "^config KSU_SUSFS$" "$KSU_KCONFIG"; then
    log "KSU_SUSFS already declared by this fork, skipping injection."
else
    python3 "${PATCHER_DIR}/kconfig_inject.py" "$KSU_KCONFIG" \
        || error "SuSFS: Kconfig inject failed!"
    log "KSU_SUSFS Kconfig injected ✅"
fi

log "Enabling SuSFS configs..."
if ! grep -q "^CONFIG_KSU_SUSFS=y" "${KERNEL_SRC}/arch/arm64/configs/gki_defconfig"; then
    cat >> "${KERNEL_SRC}/arch/arm64/configs/gki_defconfig" << 'CONFIGS'
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_SUS_OVERLAYFS=y
CONFIG_KSU_SUSFS_TRY_UMOUNT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_ENABLE_LOG=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
CONFIG_KSU_SUSFS_SUS_MAP=y
CONFIG_KSU_SUSFS_SUS_SU=y
CONFIGS
fi
log "SuSFS configs enabled ✅"

log "SuSFS integrated ✅"
