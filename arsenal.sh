#!/usr/bin/env bash
# ======================================================
# ✨ LUMINAIRE PROTOCOL — Arsenal Orchestrator
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
LUMINAIRE_PATCH_DIR="${ROOT_DIR}/luminaire"

# ======================================================
# 🚀 MAIN
# ======================================================

main() {
    echo "========================================"
    echo "  ✨ Luminaire Arsenal — ${KERNEL_VERSION}"
    echo "  🖥️ CPU: $(nproc --all) cores"
    echo "  📅 $(date)"
    echo "========================================"

    run_setup
    mkdir -p "$KERNEL_DIR" "$OUT_DIR"
    run_download

    # Wait for background apt install (started in 01_deps.sh) to finish
    if [ -n "${APT_PID:-}" ]; then
        log "Waiting for background apt install (PID ${APT_PID})..."
        if wait "$APT_PID"; then
            mkdir -p ~/.apt-cache
            sudo cp /var/cache/apt/archives/*.deb ~/.apt-cache/ 2>/dev/null || true
            log "Dependencies installed ✅"
        else
            error "Background apt install failed!"
        fi
    fi

    log "✅ Arsenal ready!"
}


# ======================================================
# 📦 SETUP
# ======================================================

run_setup() {
    echo "::group::📦 Setup"
    local setup_dir="${LUMINAIRE_PATCH_DIR}/setup"
    local scripts=(
        "${setup_dir}/00_paths.sh"
        "${setup_dir}/01_deps.sh"
        "${setup_dir}/02_ccache.sh"
        "${setup_dir}/03_clang.sh"
    )
    for script in "${scripts[@]}"; do
        [ -f "$script" ] || { warn "Setup script not found: $(basename "$script") — skipping"; continue; }
        source "$script" || error "Setup failed: $(basename "$script")"
    done
    echo "::endgroup::"
}

# ======================================================
# 📥 DOWNLOAD
# ======================================================

run_download() {
    echo "::group::📥 Arsenal Download"
    if [ "$BUILD_SYSTEM" = "KLEAF" ]; then
        source "${LUMINAIRE_PATCH_DIR}/download/kleaf.sh"
    else
        source "${LUMINAIRE_PATCH_DIR}/download/make.sh"
    fi
    log "Arsenal downloaded ✅"
    echo "::endgroup::"
}

main "$@"
