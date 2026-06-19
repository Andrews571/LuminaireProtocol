#!/usr/bin/env bash
# ======================================================
# ✨ LUMINAIRE PROTOCOL — Kernel Config
# Applied after gki_defconfig via scripts/config
# ======================================================

[ "$BUILD_SYSTEM" = "KLEAF" ] && return 0

config() {
    "${KERNEL_SRC}/scripts/config" --file "${OUT_DIR}/.config" "$@"
}

# Merge Luminaire fragment
log "Merging luminaire.fragment..."
"${KERNEL_SRC}/scripts/kconfig/merge_config.sh" -m -O "${OUT_DIR}" \
    "${OUT_DIR}/.config" \
    "${LUMINAIRE_PATCH_DIR}/config/luminaire.fragment"
log "Fragment merged ✅"

# LTO
if [ "${ENABLE_LTO}" = "THIN" ]; then
    config --disable CONFIG_LTO_CLANG_NONE
    config --enable  CONFIG_LTO_CLANG_THIN
    log "LTO: THIN ✅"
elif [ "${ENABLE_LTO}" = "FULL" ]; then
    config --disable CONFIG_LTO_CLANG_NONE
    config --disable CONFIG_LTO_CLANG_THIN
    config --enable  CONFIG_LTO_CLANG_FULL
    log "LTO: FULL ✅"
elif [ "${ENABLE_LTO}" = "NONE" ]; then
    config --enable  CONFIG_LTO_CLANG_NONE
    config --disable CONFIG_LTO_CLANG_THIN
    log "LTO: NONE ✅"
else
    log "⚠️ Unknown ENABLE_LTO value '${ENABLE_LTO}', defaulting to NONE"
    config --enable  CONFIG_LTO_CLANG_NONE
    config --disable CONFIG_LTO_CLANG_THIN
    log "LTO: NONE ✅"
fi

log "Luminaire defconfig applied ✅"
