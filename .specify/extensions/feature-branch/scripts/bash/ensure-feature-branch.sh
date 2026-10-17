#!/usr/bin/env bash
# feature-branch extension: ensure-feature-branch.sh
#
# Make sure the active Spec Kit feature's git branch is checked out before a
# Spec Kit step runs. The active feature is resolved exactly like the core
# scripts do (SPECIFY_FEATURE_DIRECTORY, then .specify/feature.json). Then:
#   - already on the feature branch      -> nothing to do       (unchanged)
#   - branch exists locally              -> git checkout        (checked_out)
#   - branch exists only on a remote     -> local tracking copy (tracked)
#   - branch does not exist anywhere     -> create from HEAD    (created)
#
# It never stashes, resets or discards changes. If git refuses the switch,
# it exits non-zero so the calling command stops.
#
# Usage: ensure-feature-branch.sh [--json]

set -e

JSON_MODE=false
for arg in "$@"; do
    case "$arg" in
        --json)
            JSON_MODE=true
            ;;
        --help|-h)
            echo "Usage: $0 [--json]"
            echo "Check out the active Spec Kit feature's git branch, or create it if it does not exist."
            exit 0
            ;;
        *)
            echo "Error: unknown argument '$arg'" >&2
            exit 2
            ;;
    esac
done

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The project root is the first directory above this script that contains .specify/.
_find_project_root() {
    local dir="$1"
    while [ "$dir" != "/" ]; do
        if [ -d "$dir/.specify" ]; then
            printf '%s\n' "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

PROJECT_ROOT="$(_find_project_root "$SCRIPT_DIR")" || {
    echo "Error: could not find the project root (.specify/) above $SCRIPT_DIR" >&2
    exit 1
}
CORE_COMMON="$PROJECT_ROOT/.specify/scripts/bash/common.sh"
if [ ! -f "$CORE_COMMON" ]; then
    echo "Error: core Spec Kit scripts not found at $CORE_COMMON" >&2
    exit 1
fi

cd "$PROJECT_ROOT"
# shellcheck source=/dev/null
source "$CORE_COMMON"

if ! command -v git >/dev/null 2>&1 || ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "[specify] Warning: Git repository not detected; skipped feature branch check" >&2
    exit 0
fi

# get_feature_paths prints its own error when no feature is active.
if ! feature_paths="$(get_feature_paths --no-persist)"; then
    echo "Error: no active feature. Run /speckit-specify first, or set SPECIFY_FEATURE_DIRECTORY." >&2
    exit 1
fi
eval "$feature_paths"

# CURRENT_BRANCH from core is SPECIFY_FEATURE when set, else the feature directory name.
WANTED="$CURRENT_BRANCH"
FEATURE_DIR_REL="${FEATURE_DIR#"$PROJECT_ROOT/"}"
PREVIOUS_BRANCH="$(git symbolic-ref --short -q HEAD || echo HEAD)"

# A ref matches when it equals WANTED or its last path segment equals WANTED,
# so "feat/001-app-shell" matches the feature directory "001-app-shell".
_matches() {
    [ "$1" = "$WANTED" ] || [ "${1##*/}" = "$WANTED" ]
}

find_local_branch() {
    local ref
    while IFS= read -r ref; do
        if _matches "$ref"; then
            printf '%s\n' "$ref"
            return 0
        fi
    done < <(git for-each-ref --format='%(refname:lstrip=2)' refs/heads)
    return 1
}

# Prints "<remote>/<branch>" for the first remote branch that matches.
find_remote_branch() {
    local ref branch
    while IFS= read -r ref; do
        branch="${ref#*/}"
        [ "$branch" = "HEAD" ] && continue
        if _matches "$branch"; then
            printf '%s\n' "$ref"
            return 0
        fi
    done < <(git for-each-ref --format='%(refname:lstrip=2)' refs/remotes)
    return 1
}

TARGET=""
switch_or_fail() {
    local err
    if ! err="$("$@" 2>&1)"; then
        echo "Error: could not switch from '$PREVIOUS_BRANCH' to feature branch '$TARGET'." >&2
        [ -n "$err" ] && printf '%s\n' "$err" >&2
        echo "Commit or stash your local changes, then rerun the command." >&2
        exit 1
    fi
}

REMOTE_REF=""
if LOCAL_REF="$(find_local_branch)"; then
    TARGET="$LOCAL_REF"
    if [ "$PREVIOUS_BRANCH" = "$TARGET" ]; then
        ACTION="unchanged"
    else
        switch_or_fail git checkout -q "$TARGET"
        ACTION="checked_out"
    fi
elif REMOTE_REF="$(find_remote_branch)"; then
    TARGET="${REMOTE_REF#*/}"
    switch_or_fail git checkout -q --track "$REMOTE_REF"
    ACTION="tracked"
else
    TARGET="$WANTED"
    switch_or_fail git checkout -q -b "$TARGET"
    ACTION="created"
fi

if $JSON_MODE; then
    printf '{"BRANCH_NAME":"%s","ACTION":"%s","PREVIOUS_BRANCH":"%s","FEATURE_DIR":"%s"}\n' \
        "$(json_escape "$TARGET")" "$ACTION" \
        "$(json_escape "$PREVIOUS_BRANCH")" "$(json_escape "$FEATURE_DIR_REL")"
else
    case "$ACTION" in
        unchanged)   echo "✓ Already on feature branch: $TARGET" ;;
        checked_out) echo "✓ Switched from $PREVIOUS_BRANCH to feature branch: $TARGET" ;;
        tracked)     echo "✓ Created local branch $TARGET tracking $REMOTE_REF" ;;
        created)     echo "✓ Created feature branch $TARGET from $PREVIOUS_BRANCH" ;;
    esac
fi
