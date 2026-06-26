#!/usr/bin/env bash

# ======================================================
# 📦 ADDON — Re:Kernel (Binder/Signal Netlink server)
# ======================================================
# Repo: https://github.com/Sakion-Team/Re-Kernel
# Provides a Netlink server in the kernel that emits
# binder transaction and signal events for frozen procs,
# enabling tombstone apps (Thanox, HASS, Scene) to react
# to app kills and freezes in real time.

log "Integrating Re:Kernel..."

REKERNEL_PATCHER="${ROOT_DIR}/luminaire/kernel/addons/rekernel_inject.py"
REKERNEL_HEADER="${KERNEL_SRC}/drivers/android/rekernel.h"

python3 "$REKERNEL_PATCHER" "$KERNEL_SRC" \
    || error "Re:Kernel: injection failed!"

[ -f "$REKERNEL_HEADER" ] \
    || error "Re:Kernel: rekernel.h not created!"

log "Re:Kernel integrated ✅"
