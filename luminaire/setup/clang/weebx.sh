#!/usr/bin/env bash

# ======================================================
# 🧰 CLANG VARIANT — WeebX (XSans0)
# ======================================================

log "Downloading WeebX Clang..."

WEEBX_URL=$(curl -fsSL \
    https://raw.githubusercontent.com/XSans0/WeebX-Clang/main/main/link.txt \
    | tr -d '[:space:]') \
    || error "WeebX: failed to fetch download URL!"
[ -n "$WEEBX_URL" ] || error "WeebX: download URL is empty!"

retry 3 run_quiet curl -fL "$WEEBX_URL" -o /tmp/clang.tar.gz \
    || error "WeebX: download failed!"
tar -xf /tmp/clang.tar.gz -C "$TOOL_CLANG_DIR" --strip-components=1
rm -f /tmp/clang.tar.gz
log "WeebX Clang downloaded ✅"
