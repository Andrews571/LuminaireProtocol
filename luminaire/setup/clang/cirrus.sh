#!/usr/bin/env bash

# ======================================================
# 🧰 CLANG VARIANT — Cirrus (Greenforce Project)
# ======================================================

log "Downloading Cirrus Clang..."

CIRRUS_URL=$(curl -fsSL https://api.github.com/repos/greenforce-project/greenforce_clang/releases/latest \
    | python3 -c "import json,sys; d=json.load(sys.stdin); print(next((x['browser_download_url'] for x in d.get('assets',[]) if x['name'].endswith('.tar.gz')), ''))") \
    || error "Cirrus: failed to query GitHub API!"
[ -n "$CIRRUS_URL" ] || error "Cirrus: no .tar.gz asset found in latest release!"

retry 3 run_quiet curl -fL "$CIRRUS_URL" -o /tmp/clang.tar.gz \
    || error "Cirrus: download failed!"
tar -xf /tmp/clang.tar.gz -C "$TOOL_CLANG_DIR" --strip-components=1
rm -f /tmp/clang.tar.gz
log "Cirrus Clang downloaded ✅"
