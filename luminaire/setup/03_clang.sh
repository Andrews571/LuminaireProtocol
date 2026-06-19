#!/usr/bin/env bash

# ======================================================
# 🧰 SETUP — GREENFORCE CLANG
# ======================================================

# Kleaf downloads its own AOSP Clang prebuilt — skip
[ "$BUILD_SYSTEM" = "KLEAF" ] && return 0

CLANG_CACHE_DIR="${HOME}/clang-cache"

if [ -d "${CLANG_CACHE_DIR}/bin" ]; then
    log "Restoring Clang from cache..."
    mkdir -p "$TOOL_CLANG_DIR"
    cp -a "${CLANG_CACHE_DIR}/." "${TOOL_CLANG_DIR}/"
    log "Clang restored ✅"
else
    log "Downloading Greenforce Clang..."
    wget -qO- https://raw.githubusercontent.com/greenforce-project/greenforce_clang/refs/heads/main/get_clang.sh \
        | bash > /dev/null 2>&1
    [ -d "${TOOL_CLANG_DIR}/bin" ] || error "Clang download failed!"
    mkdir -p "$CLANG_CACHE_DIR"
    cp -a "${TOOL_CLANG_DIR}/." "${CLANG_CACHE_DIR}/"
    log "Clang downloaded and cached ✅"
fi

set +o pipefail
CLANG_VER=$(${TOOL_CLANG_DIR}/bin/clang --version 2>&1 | head -1 || true)
CIRRUS_CLANG_VER=$(${TOOL_CLANG_DIR}/bin/clang -v 2>&1 | grep -oP '\d+\.\d+\.\d+' | head -1 || true)
set -o pipefail
if [ -n "$CIRRUS_CLANG_VER" ]; then
    COMPILER_STRING="Cirrus Clang ${CIRRUS_CLANG_VER}"
else
    COMPILER_STRING="Cirrus Clang"
    log "⚠️ Could not parse Cirrus Clang version from -v output"
fi

log "Clang ready: ${CLANG_VER}"
echo "COMPILER_STRING=${COMPILER_STRING}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
export PATH="${TOOL_CLANG_DIR}/bin:${PATH}"

log "Setting up ccache wrappers..."
mkdir -p "$TOOL_CCACHE_WRAPPERS"
for tool in $(ls "${TOOL_CLANG_DIR}/bin/" | grep -E "^clang(\+\+)?(-[0-9]+)?$"); do
    REAL_BIN="${TOOL_CLANG_DIR}/bin/${tool}"
    WRAPPER="${TOOL_CCACHE_WRAPPERS}/${tool}"
    cat > "$WRAPPER" << WRAPPER_EOF
#!/usr/bin/env bash
exec "${TOOL_CCACHE_BIN}" "${REAL_BIN}" "\$@"
WRAPPER_EOF
    chmod +x "$WRAPPER"
done
export PATH="${TOOL_CCACHE_WRAPPERS}:${PATH}"
echo "${TOOL_CCACHE_WRAPPERS}" >> "${GITHUB_PATH:-/dev/null}" 2>/dev/null || true
echo "${TOOL_CLANG_DIR}/bin" >> "${GITHUB_PATH:-/dev/null}" 2>/dev/null || true
log "Clang ready | compiler: ${COMPILER_STRING:-N/A} ✅"
