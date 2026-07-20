#!/usr/bin/env bash

# ======================================================
# ⚙️ TELEGRAM CONFIG
# ======================================================
# These are DEFAULTS only. If a same-named repository Variable is set in
# GitHub (Settings -> Secrets and variables -> Actions -> Variables), its
# value wins instead via the ${VAR:-default} fallback below. This keeps
# this file's own text stable across upstream syncs — your real values
# live in the repo's Variables, never in this tracked file.

TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:--1004391786664}"
TELEGRAM_CI_GROUP="${TELEGRAM_CI_GROUP:-SAGA_Kernel}"       # bot notifications (Test/Release/Event topics)
TELEGRAM_GROUP="${TELEGRAM_GROUP:-SAGA_Kernel}"            # community discussion group
TELEGRAM_CHANNEL="${TELEGRAM_CHANNEL:-SAGA_Kernel}"   # public channel username (for t.me links)

# Repository Event
TELEGRAM_THREAD_ID_EVENT="${TELEGRAM_THREAD_ID_EVENT:-4}"

# Test Builds — for Test mode (flash-test before being declared stable)
TELEGRAM_THREAD_ID_TEST="${TELEGRAM_THREAD_ID_TEST:-3}"

# Release Builds — for Release mode (stable build published to the channel)
TELEGRAM_THREAD_ID_RELEASE="${TELEGRAM_THREAD_ID_RELEASE:-4}"

# Telegram Channel
TELEGRAM_CHANNEL_ID="${TELEGRAM_CHANNEL_ID:--1003777184726}"

# Telegram chat - for discussion
TELEGRAM_DISCUSSION_ID="-1004466111645"
