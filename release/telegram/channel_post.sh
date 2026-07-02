#!/usr/bin/env bash

# ======================================================
# 📢 RELEASE — TELEGRAM CHANNEL POST
# ======================================================
# Agregasi semua variant links dan kirim 1 foto ke channel.
# Dipanggil dari job notify-channel setelah semua build selesai.

CAPTION_BUILDER="${LUMINAIRE_PATCH_DIR}/release/telegram/caption.py"
BANNER_DIR="${LUMINAIRE_PATCH_DIR}/release/telegram"

# Source non-sensitive Telegram config
# shellcheck source=release/telegram/config.sh
source "${LUMINAIRE_PATCH_DIR}/release/telegram/config.sh"

TELEGRAM_API_TIMEOUT="${TELEGRAM_API_TIMEOUT:-60}"
TELEGRAM_MAX_RETRIES="${TELEGRAM_MAX_RETRIES:-3}"

# ------------------------------------------------------
# Guard clauses
# ------------------------------------------------------
if [ -z "${TELEGRAM_BOT_TOKEN:-}" ]; then
    echo "⚠️ Skipping channel post: TELEGRAM_BOT_TOKEN not set"
    exit 0
fi
if [ -z "${TELEGRAM_CHANNEL_ID:-}" ]; then
    echo "⚠️ Skipping channel post: TELEGRAM_CHANNEL_ID not set in config.sh"
    exit 0
fi

# ------------------------------------------------------
# Find banner
# ------------------------------------------------------
BANNER_PATH=""
for ext in jpg jpeg png; do
    candidate="${BANNER_DIR}/banner.${ext}"
    if [ -f "$candidate" ]; then
        BANNER_PATH="$candidate"
        break
    fi
done

if [ -z "$BANNER_PATH" ]; then
    echo "⚠️ Skipping channel post: no banner found in ${BANNER_DIR}"
    exit 0
fi

# ------------------------------------------------------
# Collect variant links from artifact JSON files
# Expects: LINKS_DIR env var pointing to dir with *.json files
# Each JSON: {"variant": "VANILLA", "link": "https://t.me/c/..."}
# ------------------------------------------------------
LINKS_DIR="${LINKS_DIR:-/tmp/variant-links}"

if [ ! -d "$LINKS_DIR" ]; then
    echo "⚠️ Skipping channel post: LINKS_DIR not found (${LINKS_DIR})"
    exit 0
fi

# Parse all variant JSON files — extract links, linux_ver, kernel_version
LINKS_PARSED=$(python3 -c "
import json, glob, sys
links_dir = '${LINKS_DIR}'
result = {}
linux_ver = ''
kernel_version = ''
for f in sorted(glob.glob(links_dir + '/*.json')):
    try:
        data = json.load(open(f))
        v = data.get('variant',''); l = data.get('link','')
        if v and l:
            result[v] = l
        if not linux_ver: linux_ver = data.get('linux_ver','')
        if not kernel_version: kernel_version = data.get('kernel_version','')
    except Exception as e:
        print('[warn] ' + str(e), file=sys.stderr)
print(json.dumps({'links':result,'linux_ver':linux_ver,'kernel_version':kernel_version}))
")

VARIANT_LINKS_JSON=$(echo "$LINKS_PARSED" | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)['links']))")
LINUX_VER=$(echo "$LINKS_PARSED" | python3 -c "import json,sys; print(json.load(sys.stdin)['linux_ver'])")
KERNEL_VERSION=$(echo "$LINKS_PARSED" | python3 -c "import json,sys; print(json.load(sys.stdin)['kernel_version'])")
export LINUX_VER KERNEL_VERSION

if [ "$VARIANT_LINKS_JSON" = "{}" ] || [ -z "$VARIANT_LINKS_JSON" ]; then
    echo "⚠️ Skipping channel post: no valid variant links found"
    exit 0
fi

echo "Variant links: $VARIANT_LINKS_JSON"
echo "Linux version: $LINUX_VER | Kernel: $KERNEL_VERSION"


# ------------------------------------------------------
# Build channel caption
# ------------------------------------------------------
CAPTION_GROUP_DUMMY="/tmp/channel_post_group_dummy.txt"
CAPTION_CHANNEL_FILE="/tmp/channel_post_caption.txt"

LINUX_VER="${LINUX_VER:-N/A}" \
KERNEL_VERSION="${KERNEL_VERSION:-}" \
ADDONS="${ADDONS:-}" \
CHANGELOG="${CHANGELOG:-}" \
TELEGRAM_GROUP="${TELEGRAM_GROUP:-}" \
GITHUB_SHA="${GITHUB_SHA:-}" \
GITHUB_SERVER_URL="${GITHUB_SERVER_URL:-https://github.com}" \
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}" \
GITHUB_RUN_ID="${GITHUB_RUN_ID:-}" \
VARIANT_LINKS_JSON="$VARIANT_LINKS_JSON" \
python3 "$CAPTION_BUILDER" "$CAPTION_GROUP_DUMMY" "$CAPTION_CHANNEL_FILE" \
    || { echo "❌ Caption builder failed"; exit 1; }

CAPTION_CHANNEL="$(cat "$CAPTION_CHANNEL_FILE")"
rm -f "$CAPTION_CHANNEL_FILE" "$CAPTION_GROUP_DUMMY"

# ------------------------------------------------------
# Send photo to channel
# ------------------------------------------------------
attempt=1
while [ "$attempt" -le "$TELEGRAM_MAX_RETRIES" ]; do
    echo "📸 Sending channel post (attempt ${attempt}/${TELEGRAM_MAX_RETRIES})..."

    http_code=$(curl -s -o /tmp/tg_channel_response.json -w "%{http_code}" \
        --max-time "$TELEGRAM_API_TIMEOUT" \
        --retry 0 \
        -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendPhoto" \
        -F "chat_id=${TELEGRAM_CHANNEL_ID}" \
        -F "parse_mode=MarkdownV2" \
        -F "photo=@${BANNER_PATH}" \
        -F "caption=${CAPTION_CHANNEL}" 2>/tmp/tg_channel_curl_err.log) || http_code="000"

    response=$(cat /tmp/tg_channel_response.json 2>/dev/null || echo "")

    if [ "$http_code" = "200" ] && echo "$response" | grep -q '"ok":true'; then
        echo "Channel post sent ✅"
        break
    fi

    curl_err=$(cat /tmp/tg_channel_curl_err.log 2>/dev/null || echo "")
    case "$http_code" in
        000|429|500|502|503|504)
            echo "⚠️ Channel send failed: HTTP ${http_code} — will retry. ${curl_err}"
            ;;
        *)
            echo "❌ Channel send FAILED: HTTP ${http_code} (non-retryable). Response: ${response}"
            break
            ;;
    esac

    if [ "$attempt" -lt "$TELEGRAM_MAX_RETRIES" ]; then
        sleep_secs=$(( 2 ** attempt ))
        echo "⏳ Retrying in ${sleep_secs}s..."
        sleep "$sleep_secs"
    fi
    attempt=$(( attempt + 1 ))
done

rm -f /tmp/tg_channel_response.json /tmp/tg_channel_curl_err.log
