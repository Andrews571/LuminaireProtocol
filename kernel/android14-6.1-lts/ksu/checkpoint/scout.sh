#!/usr/bin/env bash
# ======================================================
# 🔭 Scout — checkpoint reconnaissance (pin vs candidate)
# ======================================================
# Decides which git ref (commit SHA) each tracked upstream component
# (ReSukiSU, SukiSU-Ultra, SuSFS) should build against for this run.
#
# - RUN_MODE=Release: always use the manifest's known-good pin. Never
#   queries upstream, never builds an untested candidate.
# - RUN_MODE=Test/Warming: queries upstream's latest commit. If it
#   differs from the pin and isn't already known-bad, that becomes the
#   candidate for this run — and checkpoint/engine.sh decides after
#   the build whether to promote it or blacklist it.
#
# Exports (via $GITHUB_ENV) for each relevant component:
#   <COMPONENT>_REF        — the SHA to actually build against
#   CANDIDATE_<COMPONENT>  — "true" if REF is an unverified candidate

set -eo pipefail

LUMINAIRE_PATCH_DIR="${LUMINAIRE_PATCH_DIR:-$GITHUB_WORKSPACE}"
source "${LUMINAIRE_PATCH_DIR}/functions.sh"

MANIFEST="${LUMINAIRE_PATCH_DIR}/kernel/android14-6.1-lts/ksu/checkpoint/manifest.json"
[ -f "$MANIFEST" ] || error "scout: manifest.json not found at ${MANIFEST}"

GH_API_AUTH=()
[ -n "${PERSONAL_TOKEN:-}" ] && GH_API_AUTH=(-H "Authorization: Bearer ${PERSONAL_TOKEN}")

# Fetches the latest commit SHA for a component. Never fails the build —
# a lookup problem just means "no candidate this run, use the pin".
# Args: <component name for logging> <curl command to run> <jq filter>
latest_sha_or_empty() {
    local label="$1" url="$2" jq_filter="$3"
    local body_file http_code curl_exit sha auth_args=()

    # GH_API_AUTH is a GitHub PAT — only attach it for api.github.com calls.
    # Sending it to a non-GitHub target like gitlab.com (e.g. the SuSFS
    # lookup) is a foreign/invalid Authorization header from GitLab's point
    # of view, which it rejects quickly (~300ms, consistent every run —
    # not the profile of a timeout or rate-limit). Scoping the header to
    # its actual target avoids this; the http_code/curl_exit logging below
    # gives concrete evidence if a lookup ever fails again.
    case "$url" in
        https://api.github.com/*) auth_args=("${GH_API_AUTH[@]}") ;;
    esac

    body_file="$(mktemp)"
    if http_code=$(curl -sL -o "$body_file" -w '%{http_code}' --max-time 20 \
            "${auth_args[@]}" "$url"); then
        curl_exit=0
    else
        curl_exit=$?
    fi

    if [ "$curl_exit" -ne 0 ] || [ "$http_code" != "200" ]; then
        warn "scout: couldn't reach upstream for ${label} (curl exit ${curl_exit}, HTTP ${http_code:-000}) — using pinned ref"
        rm -f "$body_file"
        echo ""
        return 0
    fi

    sha=$(jq -r "$jq_filter" "$body_file" 2>/dev/null)
    rm -f "$body_file"
    if [ -z "$sha" ] || [ "$sha" = "null" ]; then
        warn "scout: couldn't parse latest ${label} commit — using pinned ref"
        echo ""
        return 0
    fi
    echo "$sha"
}

# Resolves one component: compares latest upstream against pin + bad-list,
# exports <COMPONENT>_REF / CANDIDATE_<COMPONENT> to $GITHUB_ENV.
# Args: <component key in manifest> <env var prefix> <latest-sha (may be empty)>
resolve_component() {
    local key="$1" prefix="$2" latest="$3"
    local good bad_list is_bad ref candidate

    good=$(jq -r ".${key}.good" "$MANIFEST")
    bad_list=$(jq -c ".${key}.bad" "$MANIFEST")

    if [ "${RUN_MODE^^}" = "RELEASE" ]; then
        [ -n "$good" ] || error "scout: RUN_MODE=Release but no known-good ${key} pin exists yet — run a Test build first."
        ref="$good"; candidate="false"
        log "${prefix}: Release mode — pinned to ${ref:0:12} (no upstream check)"
    elif [ -z "$latest" ]; then
        ref="$good"; candidate="false"
        log "${prefix}: no candidate available — using pinned ${good:0:12}"
    elif [ "$latest" = "$good" ]; then
        ref="$good"; candidate="false"
        log "${prefix}: up to date at ${good:0:12}"
    else
        is_bad=$(echo "$bad_list" | jq --arg sha "$latest" 'any(. == $sha)')
        if [ "$is_bad" = "true" ]; then
            ref="$good"; candidate="false"
            warn "${prefix}: latest upstream ${latest:0:12} is known-bad — falling back to pinned ${good:0:12}"
        else
            ref="$latest"; candidate="true"
            log "${prefix}: new candidate ${latest:0:12} (pinned: ${good:-none}) — will verify this build"
        fi
    fi

    echo "${prefix}_REF=${ref}"       >> "$GITHUB_ENV"
    echo "CANDIDATE_${prefix}=${candidate}" >> "$GITHUB_ENV"
}

case "$ROOT_SOLUTION" in
    RESUKISU)
        latest=$(latest_sha_or_empty "ReSukiSU" \
            "https://api.github.com/repos/ReSukiSU/ReSukiSU/commits/main" '.sha')
        resolve_component "resukisu" "RESUKISU" "$latest"

        if [ "$SUSFS_ENABLED" = "true" ]; then
            latest=$(latest_sha_or_empty "SuSFS (ReSukiSU pairing)" \
                "https://gitlab.com/api/v4/projects/simonpunk%2Fsusfs4ksu/repository/commits/gki-android14-6.1" '.id')
            resolve_component "susfs_resukisu" "SUSFS_RESUKISU" "$latest"
        fi
        ;;
    SUKISU)
        if [ "$SUSFS_ENABLED" = "true" ]; then
            # The "builtin" branch is SukiSU-Ultra's own SUSFS-integrated
            # line — actively maintained by the SukiSU-Ultra team to stay
            # in sync with SuSFS, unlike "main" which moved to an
            # architecture (syscall_hook_manager) that isn't compatible
            # with SuSFS's adapter patches at all. So for the SUSFS case we
            # track this branch's tip directly instead of a hand-curated
            # pin pair — same simple model as ReSukiSU's tracking.
            latest=$(latest_sha_or_empty "SukiSU-Ultra (builtin)" \
                "https://api.github.com/repos/SukiSU-Ultra/SukiSU-Ultra/commits/builtin" '.sha')
            resolve_component "sukisu_builtin" "SUKISU_BUILTIN" "$latest"

            latest=$(latest_sha_or_empty "SuSFS (SukiSU pairing)" \
                "https://gitlab.com/api/v4/projects/simonpunk%2Fsusfs4ksu/repository/commits/gki-android14-6.1" '.id')
            resolve_component "susfs_sukisu" "SUSFS_SUKISU" "$latest"
        else
            # SukiSU-Ultra's own setup.sh defaults to the latest *tag* (not
            # main HEAD) when no ref is given — match that semantic here.
            tag=$(latest_sha_or_empty "SukiSU-Ultra release" \
                "https://api.github.com/repos/SukiSU-Ultra/SukiSU-Ultra/releases/latest" '.tag_name')
            latest=""
            [ -n "$tag" ] && latest=$(latest_sha_or_empty "SukiSU-Ultra" \
                "https://api.github.com/repos/SukiSU-Ultra/SukiSU-Ultra/commits/${tag}" '.sha')
            resolve_component "sukisu" "SUKISU" "$latest"
        fi
        ;;
    VANILLA)
        log "scout: VANILLA — nothing to track"
        ;;
esac
