#!/usr/bin/env bash

# ======================================================
# 📨 RELEASE — TELEGRAM
# ======================================================

TELEGRAM_API_TIMEOUT="${TELEGRAM_API_TIMEOUT:-60}"
TELEGRAM_MAX_RETRIES="${TELEGRAM_MAX_RETRIES:-3}"
TELEGRAM_MAX_FILE_BYTES=$((50 * 1024 * 1024))
TELEGRAM_CAPTION_LIMIT=1024

# ------------------------------------------------------
# Guard clauses
# ------------------------------------------------------
if [ -z "${TELEGRAM_BOT_TOKEN:-}" ]; then
    warn "Skipping Telegram: TELEGRAM_BOT_TOKEN not set"
    return 0
fi
if [ -z "${TELEGRAM_CHAT_ID:-}" ]; then
    warn "Skipping Telegram: TELEGRAM_CHAT_ID not set"
    return 0
fi
if [ -z "${TELEGRAM_THREAD_ID_ARTIFACT:-}" ]; then
    warn "Skipping Telegram: TELEGRAM_THREAD_ID_ARTIFACT not set"
    return 0
fi
if [ ! -f "${ZIP_PATH:-}" ]; then
    warn "Skipping Telegram: ZIP_PATH not set or file missing (ZIP_PATH='${ZIP_PATH:-}')"
    return 0
fi

# ------------------------------------------------------
# File size check
# ------------------------------------------------------
ZIP_SIZE_BYTES=$(stat -c%s "$ZIP_PATH" 2>/dev/null || stat -f%z "$ZIP_PATH" 2>/dev/null || echo 0)
if [ "$ZIP_SIZE_BYTES" -eq 0 ]; then
    warn "Skipping Telegram: could not determine size of ${ZIP_PATH}, or file is empty"
    return 0
fi
if [ "$ZIP_SIZE_BYTES" -gt "$TELEGRAM_MAX_FILE_BYTES" ]; then
    ZIP_SIZE_MB=$(( ZIP_SIZE_BYTES / 1024 / 1024 ))
    warn "Skipping Telegram: ${ZIP_NAME} is ${ZIP_SIZE_MB}MB, exceeds Telegram's 50MB sendDocument limit"
    return 0
fi

# ------------------------------------------------------
# Build display fields
# ------------------------------------------------------
LINUX_VER="${KERNEL_VERSION}.${SUBLEVEL}"
COMPILER_DISPLAY="${COMPILER_STRING:-N/A}"

BUILD_SYSTEM_DISPLAY="${BUILD_SYSTEM,,}"
BUILD_SYSTEM_DISPLAY="${BUILD_SYSTEM_DISPLAY^}"
if [ "${BUILD_SYSTEM}" = "MAKE" ] && [ -n "${CLANG_VARIANT:-}" ]; then
    CLANG_LABEL="${CLANG_VARIANT^}"
    BUILD_SYSTEM_DISPLAY="Make - ${CLANG_LABEL}"
fi

# Root Solution mapping
case "${ROOT_SOLUTION}" in
    VANILLA)  ROOT_SOLUTION_DISPLAY="Vanilla" ;;
    RESUKISU) ROOT_SOLUTION_DISPLAY="ReSukiSU" ;;
    SUKISU)   ROOT_SOLUTION_DISPLAY="SukiSU-Ultra" ;;
    *)        ROOT_SOLUTION_DISPLAY="${ROOT_SOLUTION}" ;;
esac

# SuSFS version
SUSFS_VER="N/A"
if [ "$SUSFS_ENABLED" = "true" ] && [ "$ROOT_SOLUTION" != "VANILLA" ]; then
    SUSFS_H="${KERNEL_SRC}/include/linux/susfs.h"
    if [ -f "$SUSFS_H" ]; then
        SUSFS_VER=$(grep -m1 'SUSFS_VERSION' "$SUSFS_H" \
            | grep -oP 'v?\d+\.\d+\.\d+' | head -1 || true)
        if [ -n "$SUSFS_VER" ]; then
            [[ "$SUSFS_VER" == v* ]] || SUSFS_VER="v${SUSFS_VER}"
        else
            SUSFS_VER="N/A"
        fi
    fi
fi

# Mountless Engine
MOUNTLESS_DISPLAY="N/A"
case ",${ADDONS}," in
    *,nomount,*)   MOUNTLESS_DISPLAY="NoMount" ;;
    *,zeromount,*) MOUNTLESS_DISPLAY="ZeroMount" ;;
esac

# Addons flags
REKERNEL_DISPLAY="Disable"
BBG_DISPLAY="Disable"
DROIDSPACES_DISPLAY="Disable"
case ",${ADDONS}," in *,rekernel,*)    REKERNEL_DISPLAY="Enable" ;; esac
case ",${ADDONS}," in *,bbg,*)         BBG_DISPLAY="Enable" ;; esac
case ",${ADDONS}," in *,droidspaces,*) DROIDSPACES_DISPLAY="Enable" ;; esac

# ------------------------------------------------------
# Escape for MarkdownV2 code fence
# Inside code block only backtick and backslash need escaping
# ------------------------------------------------------
mdv2_code_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\`/\\\`}"
    printf '%s' "$s"
}

LINUX_VER_ESC="$(mdv2_code_escape "$LINUX_VER")"
KERNEL_BRANCH_ESC="$(mdv2_code_escape "$KERNEL_BRANCH")"
BUILD_SYSTEM_ESC="$(mdv2_code_escape "$BUILD_SYSTEM_DISPLAY")"
COMPILER_ESC="$(mdv2_code_escape "$COMPILER_DISPLAY")"
LTO_ESC="$(mdv2_code_escape "${ENABLE_LTO:-NONE}")"
ROOT_SOLUTION_ESC="$(mdv2_code_escape "$ROOT_SOLUTION_DISPLAY")"
SUSFS_VER_ESC="$(mdv2_code_escape "$SUSFS_VER")"
MOUNTLESS_ESC="$(mdv2_code_escape "$MOUNTLESS_DISPLAY")"
REKERNEL_ESC="$(mdv2_code_escape "$REKERNEL_DISPLAY")"
BBG_ESC="$(mdv2_code_escape "$BBG_DISPLAY")"
DROIDSPACES_ESC="$(mdv2_code_escape "$DROIDSPACES_DISPLAY")"
DATE_ESC="$(mdv2_code_escape "$(date +'%d %b %Y')")"

# ------------------------------------------------------
# Build caption
# ------------------------------------------------------
BLOCK_LUMINAIRE="\`\`\`Luminaire
Linux        : ${LINUX_VER_ESC}
Branch       : ${KERNEL_BRANCH_ESC}
Build System : ${BUILD_SYSTEM_ESC}
Compiler     : ${COMPILER_ESC}
LTO          : ${LTO_ESC}
Date         : ${DATE_ESC}
\`\`\`"
BLOCK_ROOT="\`\`\`RootSolution
KSU   : ${ROOT_SOLUTION_ESC}
SuSFS : ${SUSFS_VER_ESC}
\`\`\`"
BLOCK_ADDONS="\`\`\`Add-ons
Mountless Engine : ${MOUNTLESS_ESC}
Re:Kernel        : ${REKERNEL_ESC}
BBG              : ${BBG_ESC}
Droidspaces      : ${DROIDSPACES_ESC}
\`\`\`"

# MarkdownV2 outside code block requires escaping special chars
mdv2_escape() {
    python3 -c "
import sys
s = sys.argv[1]
special = chr(95)+chr(42)+chr(91)+chr(93)+chr(40)+chr(41)+chr(126)+chr(96)+chr(62)+chr(35)+chr(43)+chr(45)+chr(61)+chr(124)+chr(123)+chr(125)+chr(46)+chr(33)
for ch in special:
    s = s.replace(ch, chr(92) + ch)
sys.stdout.write(s)
" "$1"
}

mdv2_escape_url() {
    python3 -c "
import sys
s = sys.argv[1]
# In MarkdownV2 inline link URL (inside parentheses), only ) and \ need escaping
s = s.replace(chr(92), chr(92)+chr(92))
s = s.replace(chr(41), chr(92)+chr(41))
sys.stdout.write(s)
" "$1"
}

COMMIT_SHORT="${GITHUB_SHA:0:7}"
COMMIT_URL="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/commit/${GITHUB_SHA}"
RUN_URL="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"

COMMIT_SHORT_ESC="$(mdv2_escape "$COMMIT_SHORT")"
COMMIT_URL_ESC="$(mdv2_escape_url "$COMMIT_URL")"
RUN_URL_ESC="$(mdv2_escape_url "$RUN_URL")"
RUN_ID_ESC="$(mdv2_escape "$GITHUB_RUN_ID")"

FOOTER="[${COMMIT_SHORT_ESC}](${COMMIT_URL_ESC}) \\| [Run \\#${RUN_ID_ESC}](${RUN_URL_ESC})"

CAPTION="${BLOCK_LUMINAIRE}
${BLOCK_ROOT}
${BLOCK_ADDONS}
${FOOTER}"

# ------------------------------------------------------
# Enforce Telegram's 1024-char caption hard limit
# ------------------------------------------------------
CAPTION_LEN=$(printf '%s' "$CAPTION" | wc -m)
if [ "$CAPTION_LEN" -gt "$TELEGRAM_CAPTION_LIMIT" ]; then
    warn "Caption is ${CAPTION_LEN} chars, exceeds Telegram's ${TELEGRAM_CAPTION_LIMIT}-char limit — truncating"
    SUFFIX=$'\n…\n```'
    KEEP=$(( TELEGRAM_CAPTION_LIMIT - ${#SUFFIX} ))
    CAPTION="$(printf '%s' "$CAPTION" | head -c "$KEEP")${SUFFIX}"
fi

# ------------------------------------------------------
# Send helper
# ------------------------------------------------------
send_document() {
    local chat_id="$1"
    local thread_id="$2"
    local caption="$3"
    local label="$4"
    local attempt=1
    local send_ok=0

    while [ "$attempt" -le "$TELEGRAM_MAX_RETRIES" ]; do
        log "📤 Sending ${ZIP_NAME} to ${label} (attempt ${attempt}/${TELEGRAM_MAX_RETRIES})..."

        local http_code
        if [ -n "$thread_id" ]; then
            http_code=$(curl -s -o /tmp/telegram_response.json -w "%{http_code}" \
                --max-time "$TELEGRAM_API_TIMEOUT" \
                --retry 0 \
                -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" \
                -F "chat_id=${chat_id}" \
                -F "message_thread_id=${thread_id}" \
                -F "parse_mode=MarkdownV2" \
                -F "document=@${ZIP_PATH};filename=${ZIP_NAME}" \
                -F "caption=${caption}" 2>/tmp/telegram_curl_err.log) || http_code="000"
        else
            http_code=$(curl -s -o /tmp/telegram_response.json -w "%{http_code}" \
                --max-time "$TELEGRAM_API_TIMEOUT" \
                --retry 0 \
                -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" \
                -F "chat_id=${chat_id}" \
                -F "parse_mode=MarkdownV2" \
                -F "document=@${ZIP_PATH};filename=${ZIP_NAME}" \
                -F "caption=${caption}" 2>/tmp/telegram_curl_err.log) || http_code="000"
        fi

        local response curl_err
        response=$(cat /tmp/telegram_response.json 2>/dev/null || echo "")
        curl_err=$(cat /tmp/telegram_curl_err.log 2>/dev/null || echo "")

        if [ "$http_code" = "200" ] && echo "$response" | grep -q '"ok":true'; then
            log "${label} sent ✅"
            send_ok=1
            break
        fi

        case "$http_code" in
            000)
                warn "Telegram send failed: connection/timeout error (${curl_err:-no details}) — will retry"
                ;;
            429|500|502|503|504)
                warn "Telegram send failed: HTTP ${http_code} (transient) — will retry. Response: ${response}"
                ;;
            *)
                warn "Telegram send FAILED: HTTP ${http_code} (non-retryable). Response: ${response}"
                break
                ;;
        esac

        if [ "$attempt" -lt "$TELEGRAM_MAX_RETRIES" ]; then
            local sleep_secs=$(( 2 ** attempt ))
            log "⏳ Retrying in ${sleep_secs}s..."
            sleep "$sleep_secs"
        fi

        attempt=$(( attempt + 1 ))
    done

    if [ "$send_ok" -ne 1 ]; then
        log "❌ Telegram delivery to ${label} failed after ${TELEGRAM_MAX_RETRIES} attempt(s)."
    fi
}

# ------------------------------------------------------
# Send to group topic
# ------------------------------------------------------
send_document \
    "$TELEGRAM_CHAT_ID" \
    "$TELEGRAM_THREAD_ID_ARTIFACT" \
    "$CAPTION" \
    "Telegram group topic"

# ------------------------------------------------------
# Send to release channel (if enabled)
# ------------------------------------------------------
if [ "${RELEASE_CHANNEL:-false}" = "true" ] && [ -n "${TELEGRAM_CHANNEL_ID:-}" ]; then
    DONATE_URL_ESC="$(mdv2_escape_url "https://sociabuzz.com/chainonyourdoor")"
    DONATE_LINE="*My dev partner insists on being paid in Whiskas\\. If this kernel's been useful, maybe help me keep the little engineer fed?* 🐱"
    DONATE_LINK="[Buy the cat some Whiskas](${DONATE_URL_ESC})"

    CAPTION_CHANNEL="${BLOCK_LUMINAIRE}
${BLOCK_ROOT}
${BLOCK_ADDONS}
${FOOTER}

${DONATE_LINE}
${DONATE_LINK}"

    CAPTION_CHANNEL_LEN=$(printf '%s' "$CAPTION_CHANNEL" | wc -m)
    if [ "$CAPTION_CHANNEL_LEN" -gt "$TELEGRAM_CAPTION_LIMIT" ]; then
        warn "Channel caption is ${CAPTION_CHANNEL_LEN} chars, truncating"
        SUFFIX=$'\n…\n```'
        KEEP=$(( TELEGRAM_CAPTION_LIMIT - ${#SUFFIX} ))
        CAPTION_CHANNEL="$(printf '%s' "$CAPTION_CHANNEL" | head -c "$KEEP")${SUFFIX}"
    fi

    send_document \
        "$TELEGRAM_CHANNEL_ID" \
        "" \
        "$CAPTION_CHANNEL" \
        "Telegram release channel"
fi

rm -f /tmp/telegram_response.json /tmp/telegram_curl_err.log

return 0
