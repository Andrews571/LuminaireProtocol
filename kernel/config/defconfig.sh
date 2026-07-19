#!/usr/bin/env bash
# ======================================================
# ✨ LUMINAIRE PROTOCOL — Kernel Config
# Applied after gki_defconfig via scripts/config
# ======================================================

config() {
    "${KERNEL_SRC}/scripts/config" --file "${OUT_DIR}/.config" "$@"
}

# Merge Luminaire fragment
log "Merging luminaire.fragment..."
"${KERNEL_SRC}/scripts/kconfig/merge_config.sh" -m -O "${OUT_DIR}" \
    "${OUT_DIR}/.config" \
    "${LUMINAIRE_PATCH_DIR}/kernel/config/luminaire.fragment"
log "Fragment merged ✅"

# LTO
if [ "${LTO_MODE}" = "THIN" ]; then
    config --disable CONFIG_LTO_CLANG_NONE
    config --enable  CONFIG_LTO_CLANG_THIN
    log "LTO: THIN ✅"
elif [ "${LTO_MODE}" = "FULL" ]; then
    config --disable CONFIG_LTO_CLANG_NONE
    config --disable CONFIG_LTO_CLANG_THIN
    config --enable  CONFIG_LTO_CLANG_FULL
    log "LTO: FULL ✅"
else
    # Covers both the explicit "NONE" value and any unrecognized value —
    # NONE is the safe fallback either way, only the log line differs.
    [ "${LTO_MODE}" = "NONE" ] \
        || warn "Unknown LTO_MODE value '${LTO_MODE}', defaulting to NONE"
    config --enable  CONFIG_LTO_CLANG_NONE
    config --disable CONFIG_LTO_CLANG_THIN
    log "LTO: NONE ✅"
fi

log "Luminaire defconfig applied ✅"

# DAMON_RECLAIM / DAMON_LRU_SORT are compiled in via the fragment above,
# but each only activates through its own module_param ("enabled",
# defaulting to false) — there's no Kconfig default for that, the kernel
# devs' own comment says it's meant to be set "via command line". Append
# it to CONFIG_CMDLINE (string config, must read-then-append or we'd
# clobber the existing console=/kasan.*/kvm-arm.* params already there).
# CONFIG_CMDLINE_EXTEND=y means this still gets merged with whatever
# cmdline the bootloader/vendor_boot provides on top of this.
DAMON_CMDLINE_EXTRA="damon_reclaim.enabled=1 damon_lru_sort.enabled=1"
CURRENT_CMDLINE=$(config --state CONFIG_CMDLINE 2>/dev/null | tr -d '"' || true)
if echo "$CURRENT_CMDLINE" | grep -q "damon_reclaim.enabled"; then
    log "DAMON: cmdline params already present ✅"
elif [ -z "$CURRENT_CMDLINE" ] || [ "$CURRENT_CMDLINE" = "undef" ]; then
    warn "DAMON: CONFIG_CMDLINE state unknown — skipping cmdline patch"
else
    config --set-str CONFIG_CMDLINE "${CURRENT_CMDLINE} ${DAMON_CMDLINE_EXTRA}"
    log "DAMON: reclaim+lru_sort enabled via CONFIG_CMDLINE ✅"
fi

if [ "${LZ4KD_ENABLED:-false}" = "true" ]; then
    config --enable CONFIG_CRYPTO_LZ4HC
    config --enable CONFIG_CRYPTO_LZ4K
    config --enable CONFIG_CRYPTO_LZ4KD
    config --enable CONFIG_LZ4K_COMPRESS
    config --enable CONFIG_LZ4K_DECOMPRESS
    config --enable CONFIG_LZ4KD_COMPRESS
    config --enable CONFIG_LZ4KD_DECOMPRESS
    LZ4KD_STATE=$(config --state CONFIG_CRYPTO_LZ4KD 2>/dev/null || echo "unknown")
    log "LZ4KD: CONFIG_CRYPTO_LZ4KD state after scripts/config --enable: ${LZ4KD_STATE}"
fi

# BBG requires baseband_guard in CONFIG_LSM — patch here because .config
# is not available when bbg.sh runs (before make defconfig)
if [ "${BBG_ENABLED:-false}" = "true" ]; then
    CURRENT_LSM=$(config --state CONFIG_LSM 2>/dev/null | tr -d '"' || true)
    if [ -z "$CURRENT_LSM" ] || [ "$CURRENT_LSM" = "undef" ]; then
        warn "BBG: CONFIG_LSM state unknown — skipping LSM patch"
    elif echo "$CURRENT_LSM" | grep -q "baseband_guard"; then
        log "BBG: baseband_guard already in CONFIG_LSM ✅"
    else
        config --set-str CONFIG_LSM "${CURRENT_LSM},baseband_guard"
        log "BBG: baseband_guard appended to CONFIG_LSM ✅"
    fi
fi
