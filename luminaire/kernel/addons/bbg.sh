#!/usr/bin/env bash

log "Setting up Baseband Guard (BBG)..."
cd "${KERNEL_SRC}"
BBG_SETUP=$(curl -LSs --fail --retry 3 --connect-timeout 30 \
    "https://github.com/vc-teahouse/Baseband-guard/raw/main/setup.sh") \
    || error "BBG: failed to download setup.sh!"
[ -n "$BBG_SETUP" ] || error "BBG: setup.sh is empty!"
echo "$BBG_SETUP" | grep -q "^#!" || error "BBG: setup.sh looks invalid (no shebang)!"
echo "$BBG_SETUP" | bash || error "BBG: setup.sh failed!"
[ -L "${KERNEL_SRC}/security/baseband-guard" ] \
    || error "BBG: inject failed — security/baseband-guard symlink not found!"

PATCHER="${LUMINAIRE_PATCH_DIR}/kernel/addons/bbg_kconfig_inject.py"
python3 "$PATCHER" "${KERNEL_SRC}/security/Kconfig" \
    || error "BBG: Kconfig inject failed!"

cd "${ROOT_DIR}"

DEFCONFIG_FILE="${KERNEL_SRC}/arch/arm64/configs/gki_defconfig"

log "Patching CONFIG_LSM in gki_defconfig to include baseband_guard..."
if grep -q "^CONFIG_LSM=" "$DEFCONFIG_FILE"; then
    if grep -q "baseband_guard" "$DEFCONFIG_FILE"; then
        log "baseband_guard already in CONFIG_LSM, skipping"
    else
        sed -i 's/^CONFIG_LSM="\?\(.*[^"]\)"\?$/CONFIG_LSM=\1,baseband_guard/' "$DEFCONFIG_FILE"
        log "baseband_guard appended to CONFIG_LSM ✅"
    fi
else
    warn "CONFIG_LSM not found in gki_defconfig — BBG may fail at build time"
fi

log "Enabling CONFIG_BBG..."
echo "CONFIG_BBG=y" >> "$DEFCONFIG_FILE"
log "BBG setup complete ✅"
