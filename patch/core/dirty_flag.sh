#!/usr/bin/env bash

# ======================================================
# 🧹 FIX — CLEAN DIRTY FLAGS
# ======================================================

sed -i 's/-dirty//' "${KERNEL_SRC}/scripts/setlocalversion"

if [ -f "${KERNEL_DIR}/build/kernel/kleaf/impl/stamp.bzl" ]; then
    sed -i "/stable_scmversion_cmd/s/-maybe-dirty//g" \
        "${KERNEL_DIR}/build/kernel/kleaf/impl/stamp.bzl"
fi

cd "${KERNEL_DIR}/common"
git config --local user.name "chainonyourdoor"
git config --local user.email "chainonyourdoor@gmail.com"
git add . && git commit -m "Luminaire: Clean dirty flags" || true
log "Dirty flags cleaned ✅"
