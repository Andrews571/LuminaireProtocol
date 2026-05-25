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
KLEAF_MANIFEST_BRANCH="common-${ANDROID_VERSION}-${KERNEL_VERSION}"

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Bootstrap path — needed before run_setup() sources 00_paths.sh
LUMINAIRE_PATCH_DIR="${ROOT_DIR}/Luminaire-Patch/common"

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

    clone_patch_repo
    run_setup

    mkdir -p "$KERNEL_DIR" "$OUT_DIR"

    run_download

    if [ "$PREPARE_ARSENAL" = "true" ]; then
        log "✅ Prep Complete!"
        exit 0
    fi

    run_branding
    run_fixes
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
# 🌀 CLONE PATCH REPO
# ======================================================

clone_patch_repo() {
    echo "::group::🌀 Luminaire-Patch"
    if [ -d "${ROOT_DIR}/Luminaire-Patch/.git" ]; then
        log "Luminaire-Patch already exists, skipping clone."
    else
        log "Cloning Luminaire-Patch..."
        git clone --depth=1 \
            https://x-access-token:${PERSONAL_TOKEN}@github.com/chainonyourdoor/Luminaire-Patch.git \
            "${ROOT_DIR}/Luminaire-Patch"
    fi
    echo "::endgroup::"
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
# 📥 DOWNLOAD
# ======================================================

run_download() {
    echo "::group::📥 Kernel Source"
    if [ "$BUILD_SYSTEM" = "KLEAF" ]; then
        source "${LUMINAIRE_PATCH_DIR}/download/kleaf.sh"
    else
        source "${LUMINAIRE_PATCH_DIR}/download/make.sh"
    fi
    SUBLEVEL="$(grep '^SUBLEVEL = ' "${KERNEL_SRC}/Makefile" | awk '{print $3}')"
    KMI_GENERATION="$(grep '^KMI_GENERATION=' \
        "${KERNEL_SRC}/build.config.common" \
        "${KERNEL_SRC}/build.config.constants" 2>/dev/null | head -1 | cut -d= -f2)"
    [ -z "$KMI_GENERATION" ] && error "KMI_GENERATION not found!"
    export SUBLEVEL KMI_GENERATION
    log "Kernel ready ✅ (sublevel: ${SUBLEVEL}, KMI: ${KMI_GENERATION})"
    echo "SUBLEVEL=${SUBLEVEL}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
    echo "::endgroup::"
}

# ======================================================
# 🏷️ BRANDING
# ======================================================

run_branding() {
    echo "::group::🏷️ Branding"
    source "${LUMINAIRE_PATCH_DIR}/branding/branding.sh" || error "Branding failed!"
    echo "::endgroup::"
}

# ======================================================
# 🔧 FIXES
# ======================================================

run_fixes() {
    echo "::group::🔧 Fixes"
    for fix in "${LUMINAIRE_PATCH_DIR}/fixes/"*.sh; do
        source "$fix" || error "Fix failed: $(basename "$fix")"
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
