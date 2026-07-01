#!/usr/bin/env bash

# ======================================================
# 🚀 ADDON — BBRv3
# TCP congestion control patch from WildKernels/kernel_patches
# ======================================================

BBRV3_PATCHES_BASE="https://github.com/WildKernels/kernel_patches/raw/main/common/bbrv3"

# Map kernel version to patch filename
case "${KERNEL_VERSION}" in
    5.10) BBRV3_PATCH="0001-net-tcp-backport-BBRv3-to-android12-5.10.patch" ;;
    5.15) BBRV3_PATCH="0001-net-tcp-backport-BBRv3-to-android13-5.15.patch" ;;
    6.1)  BBRV3_PATCH="0001-net-tcp-backport-BBRv3-to-android14-6.1.patch"  ;;
    6.6)  BBRV3_PATCH="0001-net-tcp-backport-BBRv3-to-android15-6.6.patch"  ;;
    6.12) BBRV3_PATCH="0001-net-tcp-backport-BBRv3-to-android16-6.12.patch" ;;
    *)    error "BBRv3: unsupported kernel version '${KERNEL_VERSION}'" ;;
esac

log "🚀 Applying BBRv3 patch (${BBRV3_PATCH})..."
cd "${KERNEL_SRC}"

PATCH_CONTENT=$(curl -LSs --fail --retry 3 --connect-timeout 30 \
    "${BBRV3_PATCHES_BASE}/${BBRV3_PATCH}") \
    || error "BBRv3: failed to download patch!"

[ -n "$PATCH_CONTENT" ] || error "BBRv3: downloaded patch is empty!"

echo "$PATCH_CONTENT" | patch -p1 --forward --no-backup-if-mismatch \
    || error "BBRv3: patch apply failed!"

# Extra patch needed for android12-5.10
if [ "${KERNEL_VERSION}" = "5.10" ]; then
    SYSCTL_PATCH=$(curl -LSs --fail --retry 3 --connect-timeout 30 \
        "${BBRV3_PATCHES_BASE}/sysctl_add_proc_dou8vec_minmax.patch") || true
    if [ -n "$SYSCTL_PATCH" ]; then
        if ! grep -qF 'int proc_dou8vec_minmax(' "${KERNEL_SRC}/include/linux/sysctl.h" 2>/dev/null; then
            echo "$SYSCTL_PATCH" | patch -p1 --forward --no-backup-if-mismatch || true
            SYSCTL_FIX=$(curl -LSs --fail --retry 3 --connect-timeout 30 \
                "${BBRV3_PATCHES_BASE}/sysctl_fix_data-races_in_proc_dou8vec_minmax.patch") || true
            [ -n "$SYSCTL_FIX" ] && echo "$SYSCTL_FIX" | patch -p1 --forward --no-backup-if-mismatch || true
        fi
    fi
fi

cd "${ROOT_DIR}"

export BBRV3_ENABLED=true

log "BBRv3 patch applied ✅ (configs will be set in defconfig step)"
