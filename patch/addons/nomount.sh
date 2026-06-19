#!/usr/bin/env bash

# ======================================================
# 📦 ADDON — NoMount (VFS path injection framework)
# ======================================================
# Repo: https://github.com/maxsteeel/nomount
# Status: Beta

NOMOUNT_REPO="https://github.com/maxsteeel/nomount"
NOMOUNT_DIR="/tmp/nomount_src"
NOMOUNT_PATCH_NAME="nomount_${KERNEL_VERSION}_kernel_integration.patch"

log "Integrating NoMount..."

[ -d "$NOMOUNT_DIR" ] && rm -rf "$NOMOUNT_DIR"
git clone -q --depth=1 "$NOMOUNT_REPO" "$NOMOUNT_DIR" \
    || { log "⚠️ NoMount clone failed — skipping"; return 0; }

NOMOUNT_PATCH="${NOMOUNT_DIR}/kernel/patches/${NOMOUNT_PATCH_NAME}"
if [ ! -f "$NOMOUNT_PATCH" ]; then
    log "⚠️ NoMount patch not found for kernel ${KERNEL_VERSION} — skipping"
    rm -rf "$NOMOUNT_DIR"
    return 0
fi

log "Copying NoMount source files..."
cp "${NOMOUNT_DIR}/kernel/src/nomount.c" "${KERNEL_SRC}/fs/nomount.c"
cp "${NOMOUNT_DIR}/kernel/src/nomount.h" "${KERNEL_SRC}/include/linux/nomount.h"
log "NoMount source files copied ✅"

log "Applying NoMount kernel patch..."
if patch -p1 --fuzz=10 --dry-run --reverse -d "$KERNEL_SRC" < "$NOMOUNT_PATCH" > /dev/null 2>&1; then
    log "NoMount patch already applied, skipping."
else
    patch -p1 --fuzz=10 --forward -d "$KERNEL_SRC" < "$NOMOUNT_PATCH" \
        && log "NoMount patch applied ✅" \
        || log "⚠️ NoMount patch: some hunks failed — continuing"
fi

rm -rf "$NOMOUNT_DIR"

log "Enabling NoMount config..."
cat >> "${KERNEL_SRC}/arch/arm64/configs/gki_defconfig" << 'CONFIGS'
CONFIG_NOMOUNT=y
CONFIGS

log "NoMount integrated ✅"
