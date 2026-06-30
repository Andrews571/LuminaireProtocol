#!/usr/bin/env bash

# ======================================================
# ⚙️ TELEGRAM CONFIG
# ======================================================
# Non-sensitive Telegram IDs — hardcoded here intentionally.
# Only TELEGRAM_BOT_TOKEN stays in GitHub Secrets.

# Group (forum/topic) where CI artifacts are posted
TELEGRAM_CHAT_ID="-1004391786664"
TELEGRAM_THREAD_ID_ARTIFACT="3"

# Topic for repository events (push, etc.)
TELEGRAM_THREAD_ID_EVENT="4"

# Release channel (optional — leave empty to disable)
TELEGRAM_CHANNEL_ID=""
