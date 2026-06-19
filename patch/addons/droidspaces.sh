#!/usr/bin/env bash

# ======================================================
# 📦 ADDON — Droidspaces (LXC container runtime)
# ======================================================
# Requires: 001_GKI-below-6_12-fix_sysvipc_kabi_6_7_8.patch (already applied)
# Docs: https://github.com/ravindu644/Droidspaces-OSS

log "Enabling Droidspaces support..."
cat >> "${KERNEL_SRC}/arch/arm64/configs/gki_defconfig" << 'CONFIGS'
# Droidspaces — Mandatory
CONFIG_SYSVIPC=y
CONFIG_PID_NS=y
CONFIG_IPC_NS=y
CONFIG_UTS_NS=y
CONFIG_DEVTMPFS=y
CONFIG_CGROUP_DEVICE=y

# Droidspaces — Networking (NAT mode)
CONFIG_NET_NS=y
CONFIG_NETFILTER_XT_TARGET_LOG=y
CONFIG_NETFILTER_XT_MATCH_RECENT=y

# Droidspaces — Binfmt
CONFIG_BINFMT_ELF=y
CONFIG_BINFMT_SCRIPT=y
CONFIGS
log "Droidspaces configs enabled ✅"
