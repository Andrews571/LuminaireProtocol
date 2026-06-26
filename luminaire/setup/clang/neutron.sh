#!/usr/bin/env bash

# ======================================================
# 🧰 CLANG VARIANT — Neutron (Neutron-Toolchains)
# ======================================================

log "Downloading Neutron Clang via antman..."

cd "$TOOL_CLANG_DIR"
retry 3 run_quiet curl -fL \
    https://raw.githubusercontent.com/Neutron-Toolchains/antman/main/antman \
    -o antman || error "Neutron: antman download failed!"
chmod +x antman

./antman -S || error "Neutron: antman sync failed!"
./antman --patch=glibc || warn "Neutron: glibc patch failed — continuing"
cd "$ROOT_DIR"

log "Neutron Clang downloaded ✅"
