#!/usr/bin/env bash

# ======================================================
# 🔑 ROOT SOLUTION — SukiSU-Ultra (android14-6.1-lts)
# ======================================================
# Repo: https://github.com/SukiSU-Ultra/SukiSU-Ultra

KSU_DIR="${KERNEL_SRC}/KernelSU"
PATCHER_DIR="${LUMINAIRE_PATCH_DIR}/kernel/android14-6.1-lts/ksu/sukisu"

# ======================================================
# 1. SukiSU-Ultra
# ======================================================

log "Integrating SukiSU-Ultra..."
cd "$KERNEL_SRC"
SUKISU_SETUP=$(curl -LSs --fail --retry 3 --retry-all-errors --connect-timeout 30 \
    "https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/main/kernel/setup.sh") \
    || error "SukiSU-Ultra: failed to download setup.sh!"
[ -n "$SUKISU_SETUP" ] || error "SukiSU-Ultra: setup.sh is empty!"
echo "$SUKISU_SETUP" | grep -q "^#!" || error "SukiSU-Ultra: setup.sh looks invalid (no shebang)!"
# With SuSFS enabled we need the "builtin" branch (SukiSU-Ultra's own
# SUSFS-integrated line), resolved separately from the plain main/tag pin
# used otherwise — see checkpoint/scout.sh.
if [ "${SUSFS_ENABLED:-false}" = "true" ]; then
    SUKISU_REF="${SUKISU_BUILTIN_REF:-builtin}"
fi
if [ -n "${SUKISU_REF:-}" ]; then
    log "Pinning SukiSU-Ultra to ${SUKISU_REF}"
    echo "$SUKISU_SETUP" | bash -s -- "$SUKISU_REF" || error "SukiSU-Ultra: setup.sh failed!"
else
    echo "$SUKISU_SETUP" | bash || error "SukiSU-Ultra: setup.sh failed!"
fi
[ -d "${KERNEL_SRC}/KernelSU" ] || error "SukiSU-Ultra: KernelSU dir not found after setup!"
cd "$ROOT_DIR"
log "SukiSU-Ultra integrated ✅"

# ======================================================
# 2. Branding
# ======================================================

log "Applying Luminaire branding..."
# The builtin branch (SUSFS-integrated) restructured kernel/ entirely —
# no Kbuild file, but kernel/Makefile has the identical KSU_VERSION_FULL
# lines branding.py patches, just in a different file.
if [ "${SUSFS_ENABLED:-false}" = "true" ]; then
    BRANDING_TARGET="${KSU_DIR}/kernel/Makefile"
else
    BRANDING_TARGET="${KSU_DIR}/kernel/Kbuild"
fi
python3 "${PATCHER_DIR}/branding.py" "$BRANDING_TARGET" \
    || error "SukiSU-Ultra: branding patch failed!"
log "Branding applied ✅"

# ======================================================
# 3. Kconfig
# ======================================================

log "Enabling KSU configs..."
if ! grep -q "^CONFIG_KSU=y" "${KERNEL_SRC}/arch/arm64/configs/gki_defconfig"; then
    cat >> "${KERNEL_SRC}/arch/arm64/configs/gki_defconfig" << 'CONFIGS'
CONFIG_KSU=y
CONFIG_KPM=y
CONFIGS
fi
log "Configs enabled ✅"

log "SukiSU-Ultra ready ✅"
