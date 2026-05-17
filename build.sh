#!/usr/bin/env bash
# ======================================================
# ✨ LUMINAIRE PROTOCOL
# GKI Kernel Build System — android14-6.1
# ======================================================

set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/functions.sh"

# ======================================================
# ⚙️ CONFIGURATION
# ======================================================

ANDROID_VERSION="android14"
KERNEL_VERSION="6.1"
FORMATTED_BRANCH="${ANDROID_VERSION}-${KERNEL_VERSION}-lts"

BUILD_USER="chainonyourdoor"
BUILD_HOST="LuminaireCI"

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
KERNEL_DIR="${ROOT_DIR}/kernel"
AK3_DIR="${ROOT_DIR}/AnyKernel3"
PATCHES_REPO="${ROOT_DIR}/luminaire-patches"
LOG_FILE="/tmp/luminaire-$(date +%s).log"
touch "$LOG_FILE"

BAZEL_CACHE_DIR="${HOME}/.cache/bazel"
LD_CACHE_DIR="${HOME}/.ld_cache"

# ======================================================
# 🚀 MAIN
# ======================================================

main() {
    exec 1> >(tee -a "$LOG_FILE") 2>&1

    echo ""
    log "========================================"
    log "  ✨ Luminaire Protocol Build Start"
    log "  🖥️ CPU: $(nproc --all) cores"
    log "  💾 RAM: $(free -h | grep Mem | awk '{print $2}')"
    log "  📅 $(date)"
    log "========================================"
    echo ""

    setup_environment
    download_kernel_source
    apply_fixes
    apply_patches
    build_kernel
    package_anykernel3
    send_telegram
}

# ======================================================
# 📦 SETUP BUILD ENVIRONMENT
# ======================================================

setup_environment() {
    echo "::group::📦 Setup Build Environment"
    mkdir -p "$KERNEL_DIR"

    log "Cloning patches repo..."
    git clone --depth=1 \
        https://github.com/chainonyourdoor/LuminaireProtocol-patches.git "$PATCHES_REPO"

    log "Cloning AnyKernel3..."
    git clone --depth=1 \
        https://github.com/chainonyourdoor/AnyKernel3-Luminaire.git "$AK3_DIR"

    log "Cloning AOSP build-tools..."
    git clone https://android.googlesource.com/kernel/prebuilts/build-tools \
        -b main-kernel-2025 --depth=1 "${ROOT_DIR}/kernel-build-tools"

    log "Cloning mkbootimg..."
    git clone https://android.googlesource.com/platform/system/tools/mkbootimg \
        -b main-kernel-2025 --depth=1 "${ROOT_DIR}/mkbootimg"

    export AVBTOOL="${ROOT_DIR}/kernel-build-tools/linux-x86/bin/avbtool"
    export MKBOOTIMG="${ROOT_DIR}/mkbootimg/mkbootimg.py"
    export UNPACK_BOOTIMG="${ROOT_DIR}/mkbootimg/unpack_bootimg.py"
    export BOOT_SIGN_KEY_PATH="${ROOT_DIR}/kernel-build-tools/linux-x86/share/avb/testkey_rsa2048.pem"

    echo "::endgroup::"
}

# ======================================================
# 📥 DOWNLOAD KERNEL SOURCE
# ======================================================

download_kernel_source() {
    echo "::group::📥 Kernel Source"
    log "Fetching manifest for ${FORMATTED_BRANCH}..."
    cd "$KERNEL_DIR"

    MANIFEST_URL="https://android.googlesource.com/kernel/manifest/+/refs/heads/common-${FORMATTED_BRANCH}/default.xml?format=TEXT"
    curl -fsSL "$MANIFEST_URL" | base64 -d > manifest.xml \
        || error "Failed to fetch manifest!"

    log "Downloading kernel source (parallel)..."
    sudo apt-get install -y --no-install-recommends aria2 pigz python3 > /dev/null 2>&1
    python3 "${ROOT_DIR}/fast_parallel_download.py" \
        || error "Kernel source download failed!"

    SUBLEVEL="$(grep '^SUBLEVEL = ' "${KERNEL_DIR}/common/Makefile" | awk '{print $3}')"
    log "Kernel source ready ✅ (sublevel: ${SUBLEVEL})"
    echo "SUBLEVEL=${SUBLEVEL}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true

    echo "::endgroup::"
}

# ======================================================
# 🔧 APPLY FIXES
# ======================================================

apply_fixes() {
    echo "::group::🔧 Kernel Fixes"
    cd "${KERNEL_DIR}/common"

    GLIBC_VERSION="$(ldd --version 2>/dev/null | head -n 1 | awk '{print $NF}')"
    if [ "$(printf '%s\n' "2.38" "$GLIBC_VERSION" | sort -V | head -n 1)" = "2.38" ]; then
        log "Applying GLIBC >= 2.38 fix..."
        sed -i 's/$(Q)$(MAKE) -C $(SUBCMD_SRC) OUTPUT=$(abspath $(dir $@))\/ $(abspath $@)/$(Q)$(MAKE) -C $(SUBCMD_SRC) EXTRA_CFLAGS="$(CFLAGS)" OUTPUT=$(abspath $(dir $@))\/ $(abspath $@)/' \
            tools/bpf/resolve_btfids/Makefile 2>/dev/null || true
    fi

    sed -i 's/-dirty//' scripts/setlocalversion

    if [ -f "${KERNEL_DIR}/build/kernel/kleaf/impl/stamp.bzl" ]; then
        sed -i "/stable_scmversion_cmd/s/-maybe-dirty//g" \
            "${KERNEL_DIR}/build/kernel/kleaf/impl/stamp.bzl"
        sed -i "s/build-user/${BUILD_USER}/g" \
            "${KERNEL_DIR}/build/kernel/kleaf/impl/stamp.bzl"
        sed -i "s/build-host/${BUILD_HOST}/g" \
            "${KERNEL_DIR}/build/kernel/kleaf/impl/stamp.bzl"
    fi

    git config --global user.name "github-actions[bot]"
    git config --global user.email "github-actions[bot]@users.noreply.github.com"
    git add . && git commit -m "Luminaire: Apply fixes" || true

    cd "${KERNEL_DIR}"
    MODULE_VERSION_FILE="common/kernel/module/version.c"
    if [ -f "$MODULE_VERSION_FILE" ]; then
        sed -i '/bad_version:/{:a;n;/return 0;/{s/return 0;/return 1;/;b};ba}' \
            "$MODULE_VERSION_FILE" \
            && log "Module version bypass applied ✅" \
            || log "Module version bypass: pattern not found"
    fi

    rm -rf "${KERNEL_DIR}/common/android/abi_gki_protected_exports_"*
    perl -pi -e 's/^\s*"protected_exports_list"\s*:\s*"android\/abi_gki_protected_exports_aarch64",\s*$//;' \
        "${KERNEL_DIR}/common/BUILD.bazel" 2>/dev/null || true
    sed -i 's/protected_modules = \[.*\]/protected_modules = []/' \
        "${KERNEL_DIR}/common/modules.bzl" 2>/dev/null || true

    log "Fixes applied ✅"
    echo "::endgroup::"
}

# ======================================================
# 🩹 APPLY PATCHES
# ======================================================

apply_patches() {
    echo "::group::🩹 Apply Patches"
    cd "${KERNEL_DIR}/common"

    cp "${PATCHES_REPO}/luminaire.fragment" arch/arm64/configs/luminaire.fragment
    log "Fragment copied ✅"

    if [ -d "${PATCHES_REPO}/patches" ] && [ -n "$(ls -A "${PATCHES_REPO}/patches/"*.py 2>/dev/null)" ]; then
        for script in "${PATCHES_REPO}/patches/"*.py; do
            log "Running patch script: $(basename "$script")..."
            python3 "$script" || error "Patch script failed: $script"
        done
    fi

    chmod +x scripts/setlocalversion
    : > .scmversion

    export SOURCE_DATE_EPOCH=$(date +%s)
    export KBUILD_BUILD_TIMESTAMP="$(date)"

    log "Patches applied ✅"
    echo "::endgroup::"
}

# ======================================================
# 🏗️ BUILD KERNEL (Kleaf)
# ======================================================

build_kernel() {
    echo "::group::🏗️ Build Kernel"
    cd "${KERNEL_DIR}"

    mkdir -p "$BAZEL_CACHE_DIR" "$LD_CACHE_DIR"

    log "Building with Kleaf/Bazel..."
    START_TIME=$(date +%s)

    (
        set +eo pipefail
        while true; do
            sleep 30
            ELAPSED=$(( $(date +%s) - START_TIME ))
            printf "[LOG] Still building... ⏱️ %02d:%02d:%02d elapsed\n" \
                $((ELAPSED/3600)) $((ELAPSED%3600/60)) $((ELAPSED%60))
        done
    ) &
    HEARTBEAT_PID=$!

    tools/bazel build \
        --linkopt="--thinlto-cache-dir=${LD_CACHE_DIR}" \
        --config=fast \
        --action_env=KBUILD_BUILD_USER="${BUILD_USER}" \
        --action_env=KBUILD_BUILD_HOST="${BUILD_HOST}" \
        --action_env=KBUILD_BUILD_TIMESTAMP="$(date)" \
        --defconfig_fragment=//common:arch/arm64/configs/luminaire.fragment \
        --disk_cache="${BAZEL_CACHE_DIR}" \
        //common:kernel_aarch64 \
        || { kill "$HEARTBEAT_PID" 2>/dev/null; error "Build failed!"; }

    kill "$HEARTBEAT_PID" 2>/dev/null || true
    wait "$HEARTBEAT_PID" 2>/dev/null || true

    BUILD_SECONDS=$(( $(date +%s) - START_TIME ))
    log "Build completed in ${BUILD_SECONDS}s ✅"
    echo "BUILD_SECONDS=${BUILD_SECONDS}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true

    echo "::endgroup::"
}

# ======================================================
# 📦 PACKAGE ANYKERNEL3
# ======================================================

package_anykernel3() {
    echo "::group::📦 Package AnyKernel3"

    IMAGE_PATH="${KERNEL_DIR}/bazel-bin/common/kernel_aarch64/Image"
    [ -f "$IMAGE_PATH" ] || IMAGE_PATH="${KERNEL_DIR}/out/${ANDROID_VERSION}-${KERNEL_VERSION}/dist/Image"
    [ -f "$IMAGE_PATH" ] || error "Kernel Image not found!"

    cp "$IMAGE_PATH" "${AK3_DIR}/Image"

    DATE=$(date +"%b%d")
    ZIP_NAME="LuminaireProtocol-${DATE}R${GITHUB_RUN_NUMBER:-0}.zip"
    ZIP_PATH="/tmp/${ZIP_NAME}"

    cd "$AK3_DIR"
    zip -r9 "$ZIP_PATH" . -x "*.git*" -x "*.github*" -x "*.md" -x "LICENSE"
    cd "$ROOT_DIR"

    log "ZIP ready: ${ZIP_NAME} ✅"
    echo "ZIP_NAME=${ZIP_NAME}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
    echo "ZIP_PATH=${ZIP_PATH}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true

    echo "::endgroup::"
}

# ======================================================
# 📲 TELEGRAM
# ======================================================

send_telegram() {
    echo "::group::📲 Telegram"

    LINUX_VERSION=$(grep -E "^VERSION|^PATCHLEVEL|^SUBLEVEL" \
        "${KERNEL_DIR}/common/Makefile" | awk '{print $3}' | \
        tr '\n' '.' | sed 's/\.$//')

    if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ] && [ -f "${ZIP_PATH:-}" ]; then
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" \
            -F "chat_id=${TELEGRAM_CHAT_ID}" \
            ${TELEGRAM_THREAD_ID_BUILD:+-F "message_thread_id=${TELEGRAM_THREAD_ID_BUILD}"} \
            -F "document=@${ZIP_PATH};filename=${ZIP_NAME}" \
            -F "caption=✨ <b>Luminaire Protocol</b>
Linux : ${LINUX_VERSION:-N/A}
Date  : $(date +'%d %b %Y')" \
            -F "parse_mode=HTML" || true
    fi

    echo "::endgroup::"
}

# ======================================================
# 🧹 CLEANUP
# ======================================================

cleanup() {
    if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ] && [ -f "${LOG_FILE:-}" ]; then
        CAPTION="📄 Build Log"
        [ -n "${BUILD_SECONDS:-}" ] && \
            CAPTION="✅ ${BUILD_SECONDS}s | 📦 ${ZIP_NAME:-unknown}"
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" \
            -F "chat_id=${TELEGRAM_CHAT_ID}" \
            ${TELEGRAM_THREAD_ID_LOG:+-F "message_thread_id=${TELEGRAM_THREAD_ID_LOG}"} \
            -F "document=@${LOG_FILE};filename=build-$(date +%Y%m%d-%H%M).log" \
            -F "caption=${CAPTION}" || true
    fi
}
trap cleanup EXIT

main "$@"
