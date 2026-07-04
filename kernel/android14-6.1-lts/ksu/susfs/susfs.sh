#!/usr/bin/env bash

# ======================================================
# 🧬 SuSFS — shared apply logic (any KSU fork, android14-6.1-lts)
# ======================================================
# Repo: https://gitlab.com/simonpunk/susfs4ksu (pershoot/susfs4ksu fork for
# KernelSU-Next — see the pin-resolution comment below)

# SuSFS pin resolution — SukiSU-Ultra needs an exact commit paired with a
# matching susfs4ksu commit (community-verified combo, not just "old enough").
# ReSukiSU is generally compatible with SuSFS's branch tip, so it isn't
# pinned as tightly. checkpoint/scout.sh exports the right *_REF beforehand.
#
# KernelSU-Next is a special case: its own dev branch dropped the manual
# hook API (ksu_handle_*) that simonpunk/susfs4ksu's patch targets, in favor
# of an internal syscall_hook_manager — confirmed by a real build (undefined
# ksu_handle_*/susfs_* symbols at link time, run 28714488530). pershoot
# maintains a KernelSU-Next fork (dev-susfs branch, see ksunext.sh) paired
# with their own susfs4ksu fork/branch, which is what's tracked below
# instead of upstream simonpunk/susfs4ksu for this one root solution.
if [ "$KERNEL_VARIANT" = "SUKISU" ]; then
    SUSFS_REF="${SUSFS_SUKISU_REF:-}"
    [ -n "$SUSFS_REF" ] || warn "SuSFS+SukiSU: no pin resolved — build will likely fail (see wishlist for known-good combos)"
    SUSFS_REPO="https://gitlab.com/simonpunk/susfs4ksu.git"
    SUSFS_BRANCH="gki-android14-6.1"
elif [ "$KERNEL_VARIANT" = "KSUNEXT" ]; then
    SUSFS_REF="${SUSFS_KSUNEXT_REF:-}"
    SUSFS_REPO="https://gitlab.com/pershoot/susfs4ksu.git"
    SUSFS_BRANCH="gki-android14-6.1-dev"
else
    SUSFS_REF="${SUSFS_RESUKISU_REF:-}"
    SUSFS_REPO="https://gitlab.com/simonpunk/susfs4ksu.git"
    SUSFS_BRANCH="gki-android14-6.1"
fi

KSU_DIR="${KSU_DIR:-${KERNEL_SRC}/KernelSU}"
SUSFS_DIR="/tmp/susfs4ksu"
PATCHER_DIR="${LUMINAIRE_PATCH_DIR}/kernel/android14-6.1-lts/ksu/susfs"

log "Cloning SuSFS (${SUSFS_BRANCH})..."
[ -d "$SUSFS_DIR" ] && rm -rf "$SUSFS_DIR"
git config --global http.connectTimeout 30
git config --global http.lowSpeedLimit 1000
git config --global http.lowSpeedTime 30
if [ -n "${SUSFS_REF:-}" ]; then
    log "Pinning SuSFS to ${SUSFS_REF}"
    mkdir -p "$SUSFS_DIR"
    (
        cd "$SUSFS_DIR"
        git init -q
        git remote add origin "$SUSFS_REPO"
        run_quiet git fetch --depth=1 origin "$SUSFS_REF" && git checkout -q FETCH_HEAD
    ) || {
        warn "SuSFS: server doesn't support fetching bare SHA — falling back to full clone"
        rm -rf "$SUSFS_DIR"
        retry 3 run_quiet git clone -q -b "$SUSFS_BRANCH" "$SUSFS_REPO" "$SUSFS_DIR" \
            || error "SuSFS: full clone fallback failed after 3 attempts!"
        (cd "$SUSFS_DIR" && git checkout -q "$SUSFS_REF") \
            || error "SuSFS: ${SUSFS_REF} not found on ${SUSFS_BRANCH} even after full clone!"
    }
else
    retry 3 run_quiet git clone -q --depth=1 -b "$SUSFS_BRANCH" "$SUSFS_REPO" "$SUSFS_DIR" \
        || error "SuSFS clone failed after 3 attempts!"
fi

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
        # Verify the restore actually landed — if the "internal.h" anchor was
        # itself missing/renamed upstream, sed would silently no-op and we'd
        # lose blk.h permanently without anyone noticing until link time.
        grep -qF '#include <trace/hooks/blk.h>' "${KERNEL_SRC}/fs/namespace.c" \
            || error "SuSFS: failed to restore blk.h include in namespace.c — internal.h anchor may have changed upstream!"
    fi

    # Cleanup any leftover .rej files
    find "$KERNEL_SRC" -name "*.rej" -delete 2>/dev/null || true
fi

log "Fixing namespace.c susfs declarations (safety fallback)..."
python3 "${PATCHER_DIR}/fix_namespace.py" "${KERNEL_SRC}/fs/namespace.c" \
    || error "SuSFS: namespace.c fix failed!"
log "namespace.c fixed ✅"

if [ "$KERNEL_VARIANT" = "KSUNEXT" ]; then
    # pershoot's susfs4ksu fork ships a second patch that KernelSU-Next's
    # dev-susfs branch needs alongside the main SuSFS patch — it scopes
    # down the manual hooks so they don't collide with KSU-Next's own
    # syscall_hook_manager wiring. Without it, hook symbols end up
    # undefined at link time (the same failure mode this whole pairing
    # was built to avoid — see the comment above).
    log "Applying KSU-Next scope-minimized manual hooks patch..."
    HOOKS_PATCH="${SUSFS_DIR}/kernel_patches/60_scope-minimized_manual_hooks.patch"
    if [ -f "$HOOKS_PATCH" ]; then
        if patch -p1 --fuzz=3 --dry-run --reverse -d "$KERNEL_SRC" < "$HOOKS_PATCH" > /dev/null 2>&1; then
            log "Scope-minimized manual hooks patch already applied, skipping."
        else
            patch -p1 --fuzz=3 --forward -d "$KERNEL_SRC" < "$HOOKS_PATCH" \
                && log "Scope-minimized manual hooks patch applied ✅" \
                || warn "Scope-minimized manual hooks patch: some hunks failed — continuing"
            find "$KERNEL_SRC" -name "*.rej" -delete 2>/dev/null || true
        fi
    else
        warn "KSU-Next scope-minimized hooks patch not found in this susfs4ksu fork — continuing without it"
    fi
fi

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
