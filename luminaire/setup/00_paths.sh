#!/usr/bin/env bash

# ======================================================
# 📁 SETUP — PATHS & BUILD CONFIG
# ======================================================

# Build system
BUILD_SYSTEM="${BUILD_SYSTEM:-MAKE}"
KLEAF_MANIFEST_BRANCH="common-${ANDROID_VERSION}-${KERNEL_VERSION}-lts"

# Workspace
WORKSPACE_DIR="${ROOT_DIR}/workspace"
KERNEL_DIR="${WORKSPACE_DIR}/kernel"
KERNEL_SRC="${KERNEL_DIR}/common"
OUT_DIR="${WORKSPACE_DIR}/out"
KLEAF_OUT_DIR="${KERNEL_DIR}/bazel-bin/common/kernel_aarch64"

# Patch repo paths
LUMINAIRE_PATCH_DIR="${ROOT_DIR}/luminaire"
VERSION_PATCH_DIR="${LUMINAIRE_PATCH_DIR}/kernel/${ANDROID_VERSION}-${KERNEL_VERSION}-lts"

# Build config
DEFCONFIG="gki_defconfig"
ARCH="arm64"

# Toolchain
TOOL_CLANG_DIR="${ROOT_DIR}/greenforce-clang"
TOOL_AK3_DIR="${WORKSPACE_DIR}/AnyKernel3"
TOOL_CCACHE_BIN="${ROOT_DIR}/ccache-bin/ccache"
TOOL_CCACHE_WRAPPERS="${ROOT_DIR}/ccache-wrappers"
TOOL_CROSS_COMPILE="aarch64-linux-gnu-"
TOOL_CROSS_COMPILE_COMPAT="arm-linux-gnueabi-"

# Kernel env
export GIT_CLONE_PROTECTION_ACTIVE=false
export KCFLAGS="-w"

log "Paths configured ✅ (Build System: ${BUILD_SYSTEM})"

# Default empty array — overridden by branding.sh for KLEAF
BRANDING_KLEAF_ARGS=()
