#!/usr/bin/env bash

# ======================================================
# 📥 DOWNLOAD — KLEAF (Repo Sync)
# ======================================================

if [ "${USE_KERNEL_CACHE}" = "true" ] && [ -f "${HOME}/kernel-cache/tools/bazel" ]; then
    log "Restoring Kleaf workspace from cache..."
    cp -a "${HOME}/kernel-cache/." "${KERNEL_DIR}/"
    log "Kleaf workspace restored ✅ ($(cache_freshness_note))"
else
    log "Installing repo tool..."
    command -v repo &>/dev/null || \
        { retry 3 run_quiet curl --fail -s https://storage.googleapis.com/git-repo-downloads/repo \
            -o /usr/local/bin/repo || error "Failed to download repo tool! (see output above)"; \
          chmod +x /usr/local/bin/repo; }

    log "Initializing Kleaf workspace..."
    mkdir -p "$KERNEL_DIR" && cd "$KERNEL_DIR"
    retry 3 run_quiet repo init \
        -u https://android.googlesource.com/kernel/manifest \
        -b "${KLEAF_MANIFEST_BRANCH}" \
        --depth=1 -q || error "repo init failed! (see output above)"

    log "Overriding common/ to chainonyourdoor's repo..."
    mkdir -p .repo/local_manifests
    cat > .repo/local_manifests/luminaire.xml << MANIFEST_EOF
<manifest>
  <remote name="github" fetch="https://github.com/chainonyourdoor"/>
  <remove-project name="kernel/common"/>
  <project name="LuminaireKernel-${KERNEL_VERSION}"
           path="common"
           remote="github"
           revision="${KERNEL_BRANCH}"/>
</manifest>
MANIFEST_EOF

    log "Syncing workspace..."
    retry 3 run_quiet repo sync -c -j"$(nproc --all)" --no-tags --no-clone-bundle -q \
        || error "repo sync failed! (see output above)"
    cd "$ROOT_DIR"

    log "Saving to cache..."
    mkdir -p "${HOME}/kernel-cache"
    rsync -a --delete \
      --exclude='prebuilts/ndk-r27/toolchains/llvm/prebuilt/linux-x86_64/lib/clang/*/lib/linux/riscv64' \
      --exclude='prebuilts/ndk-r27/toolchains/llvm/prebuilt/linux-x86_64/lib/clang/*/lib/linux/i386' \
      --exclude='prebuilts/ndk-r27/toolchains/llvm/prebuilt/linux-x86_64/lib/clang/*/lib/linux/x86_64' \
      --exclude='prebuilts/ndk-r27/toolchains/llvm/prebuilt/linux-x86_64/lib/clang/*/lib/wasm' \
      "${KERNEL_DIR}/" "${HOME}/kernel-cache/"
fi
