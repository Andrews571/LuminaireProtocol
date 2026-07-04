#!/usr/bin/env bash

# ======================================================
# 🔑 ROOT SOLUTION — KernelSU-Next (android14-6.1-lts)
# ======================================================
# Repo: https://github.com/KernelSU-Next/KernelSU-Next

# setup.sh clones into ${GKI_ROOT}/KernelSU-Next and symlinks
# drivers/kernelsu -> KernelSU-Next/kernel, unlike ReSukiSU/SukiSU-Ultra's
# setup.sh which both produce a "KernelSU" dir directly — KSU_DIR below is
# intentionally different from resukisu.sh/sukisu.sh for this reason.
KSU_DIR="${KERNEL_SRC}/KernelSU-Next"
PATCHER_DIR="${LUMINAIRE_PATCH_DIR}/kernel/android14-6.1-lts/ksu/ksunext"

# ======================================================
# 1. KernelSU-Next
# ======================================================

log "Integrating KernelSU-Next..."
cd "$KERNEL_SRC"
if [ "${SUSFS_ENABLED:-false}" = "true" ]; then
    # Official KernelSU-Next has no SUSFS-compatible hook API on its dev
    # branch (see susfs.sh) — pershoot's fork keeps a dev-susfs branch that
    # does, paired with their own susfs4ksu fork. Maintainer flags this
    # fork as not production-ready; tracked like any other candidate via
    # checkpoint/scout.sh.
    log "SUSFS enabled — using pershoot/KernelSU-Next's dev-susfs fork"
    KSUNEXT_SETUP_URL="https://raw.githubusercontent.com/pershoot/KernelSU-Next/dev-susfs/kernel/setup.sh"
    KSUNEXT_SETUP_REF="${KSUNEXT_SUSFS_FORK_REF:-dev-susfs}"
else
    KSUNEXT_SETUP_URL="https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/dev/kernel/setup.sh"
    KSUNEXT_SETUP_REF="${KSUNEXT_REF:-}"
fi
KSUNEXT_SETUP=$(curl -LSs --fail --retry 3 --retry-all-errors --connect-timeout 30 \
    "$KSUNEXT_SETUP_URL") \
    || error "KernelSU-Next: failed to download setup.sh!"
[ -n "$KSUNEXT_SETUP" ] || error "KernelSU-Next: setup.sh is empty!"
echo "$KSUNEXT_SETUP" | grep -q "^#!" || error "KernelSU-Next: setup.sh looks invalid (no shebang)!"
if [ -n "$KSUNEXT_SETUP_REF" ]; then
    log "Pinning KernelSU-Next to ${KSUNEXT_SETUP_REF}"
    echo "$KSUNEXT_SETUP" | bash -s -- "$KSUNEXT_SETUP_REF" || error "KernelSU-Next: setup.sh failed!"
else
    echo "$KSUNEXT_SETUP" | bash || error "KernelSU-Next: setup.sh failed!"
fi
[ -d "$KSU_DIR" ] || error "KernelSU-Next: KernelSU-Next dir not found after setup!"
cd "$ROOT_DIR"
log "KernelSU-Next integrated ✅"

# ======================================================
# 2. Branding
# ======================================================

log "Applying Luminaire branding..."
python3 "${PATCHER_DIR}/branding.py" "${KSU_DIR}/kernel/Kbuild" \
    || error "KernelSU-Next: branding patch failed!"
log "Branding applied ✅"

# ======================================================
# 3. Kconfig
# ======================================================
# No CONFIG_KPM here — KernelPatch is a SukiSU-Ultra/ReSukiSU feature,
# KernelSU-Next's Kconfig doesn't declare it.

log "Enabling KSU configs..."
if ! grep -q "^CONFIG_KSU=y" "${KERNEL_SRC}/arch/arm64/configs/gki_defconfig"; then
    cat >> "${KERNEL_SRC}/arch/arm64/configs/gki_defconfig" << 'CONFIGS'
CONFIG_KSU=y
CONFIGS
fi
log "Configs enabled ✅"

log "KernelSU-Next ready ✅"
