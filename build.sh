#!/usr/bin/env bash
# ======================================================
# ✨ LUMINAIRE PROTOCOL — Build Orchestrator
# ======================================================

set -eo pipefail

source "$(cd "$(dirname "$0")" && pwd)/functions.sh"

# ======================================================
# ⚙️ CONFIGURATION
# ======================================================

KERNEL_VERSION="${KERNEL_VERSION:?KERNEL_VERSION is not set}"

case "${KERNEL_VERSION}" in
  "5.10") ANDROID_VERSION="android13" ;;
  "5.15") ANDROID_VERSION="android13" ;;
  "6.1")  ANDROID_VERSION="android14" ;;
  "6.6")  ANDROID_VERSION="android15" ;;
  "6.12") ANDROID_VERSION="android16" ;;
  *) error "Unknown kernel version: ${KERNEL_VERSION}" ;;
esac

KERNEL_BRANCH="${ANDROID_VERSION}-${KERNEL_VERSION}-lts"

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Bootstrap path — needed before run_setup() sources 00_paths.sh
LUMINAIRE_PATCH_DIR="${ROOT_DIR}/patch"

# ======================================================
# 🚀 MAIN
# ======================================================

main() {
    echo "========================================"
    echo "  ✨ Luminaire Protocol — ${VARIANT}"
    echo "  🖥️ CPU: $(nproc --all) cores"
    echo "  💾 RAM: $(free -h | grep Mem | awk '{print $2}')"
    echo "  📅 $(date)"
    echo "========================================"

    run_setup

    mkdir -p "$KERNEL_DIR" "$OUT_DIR"

    restore_kernel_source
    run_branding
    run_variant
    run_core
    run_addons
    run_build

    if [ "$WARMING_MODE" = "true" ]; then
        log "🔥 Warming Complete — skipping packaging"
        exit 0
    fi

    run_release

    echo "========================================"
    echo "  Build Complete! — ${ZIP_NAME}"
    echo "========================================"
}


# ======================================================
# 📦 SETUP
# ======================================================

run_setup() {
    echo "::group::📦 Setup"
    for script in "${LUMINAIRE_PATCH_DIR}/setup/"*.sh; do
        source "$script" || error "Setup failed: $(basename "$script")"
    done
    echo "::endgroup::"
}

# ======================================================
# 📥 KERNEL SOURCE
# ======================================================

restore_kernel_source() {
    echo "::group::📥 Kernel Source"
    if [ "$BUILD_SYSTEM" = "KLEAF" ]; then
        source "${LUMINAIRE_PATCH_DIR}/download/kleaf.sh"
    else
        source "${LUMINAIRE_PATCH_DIR}/download/make.sh"
    fi
    log "Kernel source ready ✅"
    echo "::endgroup::"
}

# ======================================================
# 🏷️ BRANDING
# ======================================================

run_branding() {
    echo "::group::🏷️ Branding"
    SUBLEVEL="$(grep '^SUBLEVEL = ' "${KERNEL_SRC}/Makefile" | awk '{print $3}')"
    KMI_GENERATION="$(grep '^KMI_GENERATION=' \
        "${KERNEL_SRC}/build.config.common" \
        "${KERNEL_SRC}/build.config.constants" 2>/dev/null | head -1 | cut -d= -f2)"
    [ -z "$KMI_GENERATION" ] && error "KMI_GENERATION not found!"
    export SUBLEVEL KMI_GENERATION
    echo "SUBLEVEL=${SUBLEVEL}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
    source "${LUMINAIRE_PATCH_DIR}/branding/branding.sh" || error "Branding failed!"
    echo "::endgroup::"
}

# ======================================================
# 🔑 VARIANT
# ======================================================

run_variant() {
    local script="${VERSION_PATCH_DIR}/ksu/${VARIANT,,}.sh"
    [ -f "$script" ] || return 0
    echo "::group::🔑 Variant (${VARIANT})"
    source "$script" || error "Variant script failed: $(basename "$script")"
    echo "::endgroup::"
}

# ======================================================
# 🔧 CORE
# ======================================================

run_core() {
    echo "::group::🔧 Core"
    for script in "${LUMINAIRE_PATCH_DIR}/core/"*.sh; do
        source "$script" || error "Core script failed: $(basename "$script")"
    done
    echo "::endgroup::"
}

# ======================================================
# ⚡ ADDONS
# ======================================================

run_addons() {
    [ -z "${ADDONS:-}" ] && return 0
    echo "::group::⚡ Addons"
    IFS=',' read -ra ADDON_LIST <<< "$ADDONS"
    for addon in "${ADDON_LIST[@]}"; do
        addon="${addon// /}"
        local script="${LUMINAIRE_PATCH_DIR}/addons/${addon}.sh"
        if [ -f "$script" ]; then
            source "$script" || error "Addon failed: ${addon}"
        else
            log "⚠️ Addon not found: ${addon}"
        fi
    done
    echo "::endgroup::"
}

# ======================================================
# 🏗️ BUILD
# ======================================================

run_build() {
    echo "::group::🏗️ Build Kernel (${BUILD_SYSTEM})"
    if [ "$BUILD_SYSTEM" = "KLEAF" ]; then
        source "${LUMINAIRE_PATCH_DIR}/build/kleaf.sh"
    else
        source "${LUMINAIRE_PATCH_DIR}/build/make.sh"
    fi
    echo "::endgroup::"
}

# ======================================================
# 🚀 RELEASE
# ======================================================

run_release() {
    echo "::group::🚀 Release"
    for script in "${LUMINAIRE_PATCH_DIR}/release/"*.sh; do
        source "$script" || error "Release failed: $(basename "$script")"
    done
    echo "::endgroup::"
}

main "$@"
