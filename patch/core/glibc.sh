#!/usr/bin/env bash

# ======================================================
# 🔧 FIX — GLIBC >= 2.38
# ======================================================

GLIBC_VERSION="$(ldd --version 2>/dev/null | head -n 1 | awk '{print $NF}')"
if [ "$(printf '%s\n' "2.38" "$GLIBC_VERSION" | sort -V | head -n 1)" = "2.38" ]; then
    log "Applying GLIBC >= 2.38 fix..."
    sed -i 's/$(Q)$(MAKE) -C $(SUBCMD_SRC) OUTPUT=$(abspath $(dir $@))\/ $(abspath $@)/$(Q)$(MAKE) -C $(SUBCMD_SRC) EXTRA_CFLAGS="$(CFLAGS)" OUTPUT=$(abspath $(dir $@))\/ $(abspath $@)/' \
        "${KERNEL_DIR}/common/tools/bpf/resolve_btfids/Makefile" 2>/dev/null || true
fi

log "GLIBC fix applied ✅"
