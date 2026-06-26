#!/usr/bin/env bash

# ======================================================
# 🔓 MODULE VERSION BYPASS
# ======================================================

MODULE_VERSION_FILE="${KERNEL_SRC}/kernel/module/version.c"
PATCHER="${LUMINAIRE_PATCH_DIR}/kernel/core/module_bypass_patch.py"

if [ -f "$MODULE_VERSION_FILE" ]; then
    python3 "$PATCHER" "$MODULE_VERSION_FILE" \
        || error "Module version bypass: patch script failed!"
    log "Module version bypass applied ✅"
fi
