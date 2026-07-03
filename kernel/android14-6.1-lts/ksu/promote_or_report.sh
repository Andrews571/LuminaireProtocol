#!/usr/bin/env bash
# ======================================================
# 📌 Promote or Report — post-build pin update
# ======================================================
# Runs after the build step (always, even on failure).
#
# - Candidate succeeded  -> promote it: manifest's "good" becomes this SHA.
# - Candidate failed     -> blacklist it: append to "bad", "good" untouched
#                           (this IS the rollback — nothing else changes).
# - No candidate was used this run -> nothing to do.
#
# Matrix jobs (RESUKISU / SUKISU) run in parallel and may both try to
# write manifest.json at the same time, so every write goes through a
# fetch-rebase-push retry loop instead of a single commit+push.
#
# Args: <build outcome: "success" | "failure"> <space-separated component keys to check, e.g. "resukisu susfs">

set -eo pipefail

LUMINAIRE_PATCH_DIR="${LUMINAIRE_PATCH_DIR:-$GITHUB_WORKSPACE}"
source "${LUMINAIRE_PATCH_DIR}/functions.sh"
cd "$LUMINAIRE_PATCH_DIR"

BUILD_OUTCOME="$1"
shift
COMPONENTS=("$@")

MANIFEST_REL="kernel/android14-6.1-lts/ksu/manifest.json"
MANIFEST="${LUMINAIRE_PATCH_DIR}/${MANIFEST_REL}"

any_candidate_used="false"
for key in "${COMPONENTS[@]}"; do
    prefix="${key^^}"
    candidate_var="CANDIDATE_${prefix}"
    [ "${!candidate_var:-false}" = "true" ] && any_candidate_used="true"
done

if [ "$any_candidate_used" = "false" ]; then
    log "promote_or_report: no candidate ref used this run — nothing to update"
    exit 0
fi

[ -n "${PERSONAL_TOKEN:-}" ] || error "promote_or_report: PERSONAL_TOKEN not set — cannot push manifest update"

git config --global user.name  "luminaire-bot"
git config --global user.email "luminaire-bot@users.noreply.github.com"

# Real fix for the github-actions[bot]/403 push failure lives in build.yml's
# Start-Build checkout step (persist-credentials: false), not here. A
# previous attempt tried `git config --unset-all
# http.https://github.com/.extraheader` at this point, but actions/checkout
# v6+ no longer writes that key into this repo's local .git/config — it's
# persisted via a global `includeIf.gitdir` pointing at a separate file
# under $RUNNER_TEMP, so there was nothing here to unset and the override
# kept winning silently. Confirmed against actions/checkout's own v6
# changelog/issue tracker (PR "Persist creds to a separate file").
REMOTE="https://x-access-token:${PERSONAL_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"

# Applies one jq patch to manifest.json on top of the latest main and
# pushes, retrying on a fast-forward conflict from a concurrent matrix job.
apply_and_push() {
    local jq_patch="$1" commit_msg="$2"
    local attempt=1 max_attempts=5

    while [ "$attempt" -le "$max_attempts" ]; do
        run_quiet git fetch "$REMOTE" main
        # Must actually move local HEAD to FETCH_HEAD before committing —
        # git fetch alone doesn't. Without this, every retry re-commits on
        # top of the same stale parent, so a real conflict (a concurrent
        # matrix job's push) fails identically on every attempt and this
        # loop can never actually recover (confirmed with a real two-clone
        # repro before landing this fix: 0/5 attempts succeeded without
        # this line, 1/1 with it). workspace/ is gitignored, so this
        # doesn't touch the in-progress kernel source tree.
        git reset -q --hard FETCH_HEAD

        jq "$jq_patch" "$MANIFEST" > "${MANIFEST}.tmp" && mv "${MANIFEST}.tmp" "$MANIFEST"

        (
            git add "$MANIFEST_REL"
            git commit -q -m "$commit_msg" 2>/dev/null || { echo "nothing to commit"; exit 0; }
            git push "$REMOTE" "HEAD:main"
        ) && return 0

        warn "promote_or_report: push conflict (attempt ${attempt}/${max_attempts}) — retrying..."
        attempt=$(( attempt + 1 ))
        sleep $(( RANDOM % 5 + 2 ))
    done

    error "promote_or_report: failed to push manifest update after ${max_attempts} attempts"
}

# Opens (or leaves open) a GitHub Issue for a broken upstream component,
# de-duplicated by a stable title so repeated failed re-tests don't spam.
file_issue() {
    local key="$1" ref="$2"
    local title="🔴 Upstream build failure: ${key}"
    local existing
    existing=$(gh issue list --repo "$GITHUB_REPOSITORY" --state open --search "in:title \"${title}\"" --json number --jq '.[0].number' 2>/dev/null || true)

    local body="Latest upstream commit \`${ref}\` for **${key}** failed to build (run: ${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}).

Still pinned to the last known-good commit — no action needed unless you want to investigate upstream. This issue will auto-close once a build succeeds again for ${key}."

    if [ -n "$existing" ] && [ "$existing" != "null" ]; then
        gh issue comment "$existing" --repo "$GITHUB_REPOSITORY" --body "$body" || warn "file_issue: couldn't comment on existing issue #${existing}"
    else
        gh issue create --repo "$GITHUB_REPOSITORY" --title "$title" --body "$body" --label "upstream-broken" || warn "file_issue: couldn't create issue for ${key}"
    fi
}

close_issue_if_open() {
    local key="$1"
    local title="🔴 Upstream build failure: ${key}"
    local existing
    existing=$(gh issue list --repo "$GITHUB_REPOSITORY" --state open --search "in:title \"${title}\"" --json number --jq '.[0].number' 2>/dev/null || true)
    [ -n "$existing" ] && [ "$existing" != "null" ] && \
        gh issue close "$existing" --repo "$GITHUB_REPOSITORY" --comment "✅ Build succeeded again — pin promoted to a new known-good commit." 2>/dev/null || true
}

for key in "${COMPONENTS[@]}"; do
    prefix="${key^^}"
    candidate_var="CANDIDATE_${prefix}"
    [ "${!candidate_var:-false}" = "true" ] || continue

    ref_var="${prefix}_REF"
    ref="${!ref_var}"

    if [ "$BUILD_OUTCOME" = "success" ]; then
        log "promote_or_report: promoting ${key} pin to ${ref:0:12}"
        apply_and_push ".${key}.good = \"${ref}\"" "chore: bump ${key} pin to ${ref:0:12} (verified via run ${GITHUB_RUN_ID})"
        close_issue_if_open "$key"
    else
        warn "promote_or_report: blacklisting ${key} candidate ${ref:0:12} (build failed)"
        apply_and_push ".${key}.bad |= (. + [\"${ref}\"] | unique)" "chore: mark ${key} candidate ${ref:0:12} as known-bad (run ${GITHUB_RUN_ID})"
        file_issue "$key" "$ref"
    fi
done
