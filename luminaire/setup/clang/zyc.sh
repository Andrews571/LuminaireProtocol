#!/usr/bin/env bash

# ======================================================
# 🧰 CLANG VARIANT — ZyC (ZyCromerZ)
# ======================================================

log "Downloading ZyC Clang..."

ZYC_URL=$(curl -fsSL \
    https://raw.githubusercontent.com/ZyCromerZ/Clang/main/Clang-main-link.txt \
    | tr -d '[:space:]') \
    || error "ZyC: failed to fetch download URL!"
[ -n "$ZYC_URL" ] || error "ZyC: download URL is empty!"

retry 3 run_quiet curl -fL "$ZYC_URL" -o /tmp/clang.tar.gz \
    || error "ZyC: download failed!"

STRIP=1
BIN_PATH=$(tar -tf /tmp/clang.tar.gz 2>/dev/null | grep -m1 'bin/clang$' || true)
if [ -n "$BIN_PATH" ]; then
    DEPTH=$(echo "$BIN_PATH" | tr '/' '\n' | wc -l)
    STRIP=$(( DEPTH - 2 ))
    [ "$STRIP" -lt 0 ] && STRIP=0
fi

tar -xf /tmp/clang.tar.gz -C "$TOOL_CLANG_DIR" --strip-components="${STRIP}"
rm -f /tmp/clang.tar.gz
log "ZyC Clang downloaded ✅"
