#!/usr/bin/env bash

# ======================================================
# 🔑 ROOT SOLUTION — ReSukiSU (android14-6.1-lts)
# ======================================================
# Repo: https://github.com/ReSukiSU/ReSukiSU

KSU_DIR="${KERNEL_SRC}/KernelSU"
PATCHER_DIR="${LUMINAIRE_PATCH_DIR}/kernel/android14-6.1-lts/ksu/resukisu"

# ======================================================
# 1. ReSukiSU
# ======================================================

log "Integrating ReSukiSU..."
cd "$KERNEL_SRC"
RESUKISU_SETUP=$(curl -LSs --fail --retry 3 --retry-all-errors --connect-timeout 30 \
    "https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh") \
    || error "ReSukiSU: failed to download setup.sh!"
[ -n "$RESUKISU_SETUP" ] || error "ReSukiSU: setup.sh is empty!"
echo "$RESUKISU_SETUP" | grep -q "^#!" || error "ReSukiSU: setup.sh looks invalid (no shebang)!"
if [ -n "${RESUKISU_REF:-}" ]; then
    log "Pinning ReSukiSU to ${RESUKISU_REF}"
    echo "$RESUKISU_SETUP" | bash -s -- "$RESUKISU_REF" || error "ReSukiSU: setup.sh failed!"
else
    echo "$RESUKISU_SETUP" | bash || error "ReSukiSU: setup.sh failed!"
fi
[ -d "${KERNEL_SRC}/KernelSU" ] || error "ReSukiSU: KernelSU dir not found after setup!"
cd "$ROOT_DIR"
log "ReSukiSU integrated ✅"

# ======================================================
# 2. Branding
# ======================================================

log "Applying Luminaire branding..."
python3 "${PATCHER_DIR}/branding.py" "${KSU_DIR}/kernel/Kbuild" \
    || error "ReSukiSU: branding patch failed!"
log "Branding applied ✅"

# ======================================================
# 3. Multi-Manager
# ======================================================

log "Patching multi-manager support..."
python3 "${PATCHER_DIR}/multimanager.py" \
    "${KSU_DIR}/kernel/manager/manager_sign.h" \
    "${KSU_DIR}/kernel/manager/apk_sign.c" \
    || error "ReSukiSU: multi-manager patch failed!"
log "Multi-manager patched ✅"

# ======================================================
# 4. KSU-Next compat
# ======================================================

log "Patching KSU-Next manager compat..."
python3 "${PATCHER_DIR}/ksunext_compat.py" \
    "${KSU_DIR}/kernel/supercall/dispatch.c" \
    || error "ReSukiSU: KSU-Next compat patch failed!"
log "KSU-Next compat patched ✅"

# ======================================================
# 5. Kconfig
# ======================================================

log "Enabling KSU configs..."
if ! grep -q "^CONFIG_KSU=y" "${KERNEL_SRC}/arch/arm64/configs/gki_defconfig"; then
    cat >> "${KERNEL_SRC}/arch/arm64/configs/gki_defconfig" << 'CONFIGS'
CONFIG_KSU=y
CONFIG_KPM=y
CONFIGS
fi
log "Configs enabled ✅"

log "ReSukiSU ready ✅"
