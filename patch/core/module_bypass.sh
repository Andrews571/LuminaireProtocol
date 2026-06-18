#!/usr/bin/env bash

# ======================================================
# 🔓 FIX — MODULE VERSION BYPASS
# ======================================================

MODULE_VERSION_FILE="${KERNEL_DIR}/common/kernel/module/version.c"
if [ -f "$MODULE_VERSION_FILE" ]; then
    sed -i '/bad_version:/{:a;n;/return 0;/{s/return 0;/return 1;/;b};ba}' \
        "$MODULE_VERSION_FILE" \
        && log "Module version bypass applied ✅" \
        || log "Module version bypass: pattern not found"
fi
