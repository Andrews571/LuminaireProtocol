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
python3 "${PATCHER_DIR}/branding.py" "${KSU_DIR}/kernel/Kbuild" \
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
