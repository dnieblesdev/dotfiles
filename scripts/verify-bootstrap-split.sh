#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVE_DIR="$(find "$REPO_ROOT/openspec/changes/archive" -maxdepth 1 -type d -name '*-split-dotfiles-bootstrap-identity' | head -n 1)"

missing_path() {
    local path="$1"
    if [ -e "$REPO_ROOT/$path" ] || [ -L "$REPO_ROOT/$path" ]; then
        printf 'removed bootstrap surface still exists: %s\n' "$path" >&2
        return 1
    fi
}

missing_path installer/install.sh
missing_path installer/dotlink
missing_path cmd/bootstrap-controller
missing_path internal/controller
missing_path bootstrap-controller
missing_path go.mod
missing_path installer/lib
missing_path installer/lib/catalog.sh
missing_path installer/lib/controller.sh
missing_path installer/lib/planner.sh
missing_path installer/lib/state.sh
missing_path installer/lib/util.sh

removed_bootstrap_context_allowed() {
    local file="$1"
    local line="$2"

    awk -v line="$line" 'NR >= line - 2 && NR <= line + 2 { print }' "$file" \
        | grep -qi -E 'removed|no[[:space:]-]+(legacy[[:space:]-]+installer[[:space:]-]+)?(compatibility|shim|preservation)|no[[:space:]-]+longer[[:space:]-]+authoritative|not[[:space:]-]+authoritative|non-authoritative|no .*authoritative|must[[:space:]]+not[[:space:]]+require[[:space:]]+compatibility|without[[:space:]]+shims?|superseded|recover|history|external|sibling|handoff|future repository boundary|No local'
}

stale_removed_bootstrap_refs() {
    local pattern="$1"
    shift
    local found=1
    local match file rest line

    while IFS= read -r match; do
        file="${match%%:*}"
        rest="${match#*:}"
        line="${rest%%:*}"

        if ! removed_bootstrap_context_allowed "$file" "$line"; then
            printf '%s\n' "$match"
            found=0
        fi
    done < <(grep -R -n -E "$pattern" "$@" 2>/dev/null || true)

    return "$found"
}

if stale_removed_bootstrap_refs 'installer/install\.sh|installer/dotlink|cmd/bootstrap-controller|internal/controller|bootstrap-controller' \
    "$REPO_ROOT/README.md" "$REPO_ROOT/docs" "$REPO_ROOT/openspec/specs"; then
    printf 'stale authoritative bootstrap reference found\n' >&2
    exit 1
fi

if grep -R -n -i -E 'shell-owned behavior first|shell-owned bootstrap|shell-owned.*canonical|shell-first (bootstrap )?(canonical|canonicality|authority)|shell behavior.*resolved in favor|resolved in favor of the shell|frontend changes must preserve shell contract|shell-based installer behavior is canonical|shell bootstrap is canonical|Go/TUI surface is optional frontend behavior|Go/TUI path described as optional|Go controller is optional' \
    "$REPO_ROOT/README.md" "$REPO_ROOT/docs" "$REPO_ROOT/openspec/specs" 2>/dev/null \
    | grep -v -i -E 'superseded|no longer authoritative|external|sibling|handoff|removed|not authoritative|non-authoritative|future repository boundary|ADR'; then
    printf 'stale shell-first canonicality reference found\n' >&2
    exit 1
fi

if grep -R -n -E 'installer/lib|catalog\.sh|planner\.sh|state\.sh|util\.sh' \
    "$REPO_ROOT/bin" "$REPO_ROOT/dotlink" "$REPO_ROOT/profiles" "$REPO_ROOT/scripts" 2>/dev/null \
    | grep -v -E 'scripts/verify-bootstrap-split\.sh'; then
    printf 'stale operational bootstrap library reference found\n' >&2
    exit 1
fi

if [ -z "$ARCHIVE_DIR" ] || [ ! -d "$ARCHIVE_DIR" ]; then
    printf 'archive directory for split-dotfiles-bootstrap-identity not found\n' >&2
    exit 1
fi

if grep -R -n -E 'installer/lib|catalog\.sh|planner\.sh|state\.sh|util\.sh' \
    "$REPO_ROOT/README.md" "$REPO_ROOT/docs" "$REPO_ROOT/openspec/specs" "$ARCHIVE_DIR" 2>/dev/null \
    | grep -v -E 'removed|Removed|no longer authoritative|not authoritative|non-authoritative|superseded|Superseded|historical|archive|external|sibling|handoff'; then
    printf 'stale authoritative bootstrap library reference found\n' >&2
    exit 1
fi

printf 'bootstrap split verification passed\n'
