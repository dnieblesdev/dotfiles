#!/usr/bin/env bash

set -euo pipefail

DOTLINK_PROFILE_NAME=""
DOTLINK_PROFILE_DESCRIPTION=""
DOTLINK_PROFILE_MODULES=()
DOTLINK_KNOWN_MODULES=(bash git zsh config)

dotlink_manifest_error() {
    printf 'dotlink: %s\n' "$1" >&2
}

dotlink_is_known_module() {
    local repo_root="$1"
    local module="$2"
    local known_module

    [ -d "$repo_root/$module" ] || return 1
    case "$module" in
        bin|dotlink|docs|installer|openspec|profiles|cmd|internal|skills|repo|scripts|.*|*/*) return 1 ;;
    esac
    for known_module in "${DOTLINK_KNOWN_MODULES[@]}"; do
        [ "$module" = "$known_module" ] && return 0
    done
    return 1
}

dotlink_list_known_modules() {
    local repo_root="$1"
    local known_module
    for known_module in "${DOTLINK_KNOWN_MODULES[@]}"; do
        [ -d "$repo_root/$known_module" ] && printf '%s\n' "$known_module"
    done
}

dotlink_validate_manifest_line() {
    local line="$1"

    [[ "$line" =~ ^[[:space:]]*$ ]] && return 0
    [[ "$line" =~ ^[[:space:]]*# ]] && return 0
    [[ "$line" =~ ^[[:space:]]*DOTLINK_PROFILE_NAME=\"[A-Za-z0-9._[:space:]-]*\"[[:space:]]*$ ]] && return 0
    [[ "$line" =~ ^[[:space:]]*DOTLINK_PROFILE_DESCRIPTION=\"[A-Za-z0-9.,:_/()[:space:]-]*\"[[:space:]]*$ ]] && return 0
    [[ "$line" =~ ^[[:space:]]*DOTLINK_PROFILE_MODULES=\([A-Za-z0-9_[:space:]-]*\)[[:space:]]*$ ]] && return 0

    return 1
}

dotlink_validate_manifest() {
    local manifest="$1"
    local line

    [ -f "$manifest" ] || {
        dotlink_manifest_error "profile manifest not found: $manifest"
        return 1
    }

    while IFS= read -r line || [ -n "$line" ]; do
        if ! dotlink_validate_manifest_line "$line"; then
            dotlink_manifest_error "profile manifest contains non-declarative syntax: $manifest"
            return 1
        fi
    done < "$manifest"
}

dotlink_load_profile() {
    local repo_root="$1"
    local profile="$2"
    local manifest="$repo_root/profiles/$profile.sh"
    local module

    case "$profile" in
        */*|*..*|.*|"")
            dotlink_manifest_error "invalid profile name: $profile"
            return 1
            ;;
    esac

    dotlink_validate_manifest "$manifest" || return 1

    DOTLINK_PROFILE_NAME=""
    DOTLINK_PROFILE_DESCRIPTION=""
    DOTLINK_PROFILE_MODULES=()

    # shellcheck source=/dev/null
    source "$manifest"

    if [ "${#DOTLINK_PROFILE_MODULES[@]}" -eq 0 ]; then
        dotlink_manifest_error "profile has no modules: $profile"
        return 1
    fi

    for module in "${DOTLINK_PROFILE_MODULES[@]}"; do
        if ! dotlink_is_known_module "$repo_root" "$module"; then
            dotlink_manifest_error "profile '$profile' references unknown module: $module"
            return 1
        fi
    done
}
