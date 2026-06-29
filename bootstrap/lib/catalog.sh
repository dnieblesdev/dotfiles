#!/usr/bin/env bash

set -euo pipefail

BOOTSTRAP_SCHEMA_VERSION=1
BOOTSTRAP_CATALOG_VERSION=1

BOOTSTRAP_ACTION_ORDER=(
    system-packages
    homebrew-bootstrap
    brew-tools
    dotfiles-clone
    dotfiles-backup
    dotfiles-link
    runtime-nvm
    runtime-uv
    runtime-rustup
)

declare -A BOOTSTRAP_ACTION_LABELS=(
    [system-packages]="Distro system packages"
    [homebrew-bootstrap]="Homebrew bootstrap"
    [brew-tools]="Brew-managed developer tools"
    [dotfiles-clone]="Clone or update dotfiles repo"
    [dotfiles-backup]="Back up existing shell files"
    [dotfiles-link]="Link dotfiles into the home directory"
    [runtime-nvm]="Install nvm runtime manager"
    [runtime-uv]="Install uv runtime manager"
    [runtime-rustup]="Install rustup runtime manager"
)

declare -A BOOTSTRAP_ACTION_GROUPS=(
    [system-packages]="system"
    [homebrew-bootstrap]="brew"
    [brew-tools]="brew"
    [dotfiles-clone]="dotfiles"
    [dotfiles-backup]="dotfiles"
    [dotfiles-link]="dotfiles"
    [runtime-nvm]="runtime"
    [runtime-uv]="runtime"
    [runtime-rustup]="runtime"
)

declare -A BOOTSTRAP_ACTION_DEPS=(
    [system-packages]=""
    [homebrew-bootstrap]="system-packages"
    [brew-tools]="homebrew-bootstrap"
    [dotfiles-clone]="system-packages"
    [dotfiles-backup]="dotfiles-clone"
    [dotfiles-link]="dotfiles-clone dotfiles-backup"
    [runtime-nvm]="system-packages"
    [runtime-uv]="system-packages"
    [runtime-rustup]="system-packages"
)

declare -A BOOTSTRAP_ACTION_PRIVILEGES=(
    [system-packages]="elevated"
    [homebrew-bootstrap]="user"
    [brew-tools]="user"
    [dotfiles-clone]="user"
    [dotfiles-backup]="user"
    [dotfiles-link]="user"
    [runtime-nvm]="user"
    [runtime-uv]="user"
    [runtime-rustup]="user"
)

bootstrap_action_normalize() {
    case "$1" in
        homebrew) printf '%s\n' homebrew-bootstrap ;;
        *) printf '%s\n' "$1" ;;
    esac
}

bootstrap_action_known() {
    local action="$1"
    action="$(bootstrap_action_normalize "$action")"

    case "$action" in
        system-packages|homebrew-bootstrap|brew-tools|dotfiles-clone|dotfiles-backup|dotfiles-link|runtime-nvm|runtime-uv|runtime-rustup)
            return 0
            ;;
    esac

    return 1
}

bootstrap_action_deps_array() {
    local action="$1"
    action="$(bootstrap_action_normalize "$action")"
    local array_name="$2"
    local deps_value="${BOOTSTRAP_ACTION_DEPS[$action]:-}"
    local -a dep_items=()

    if [ -n "$deps_value" ]; then
        IFS=' ' read -r -a dep_items <<<"$deps_value"
    fi

    local -n target_ref="$array_name"
    target_ref=("${dep_items[@]}")
}

bootstrap_action_privilege() {
    local action="$1"
    action="$(bootstrap_action_normalize "$action")"

    if [ -z "${BOOTSTRAP_ACTION_PRIVILEGES[$action]+x}" ] || [ -z "${BOOTSTRAP_ACTION_PRIVILEGES[$action]}" ]; then
        printf 'Missing privilege metadata for action: %s\n' "$action" >&2
        return 4
    fi

    printf '%s\n' "${BOOTSTRAP_ACTION_PRIVILEGES[$action]}"
}

bootstrap_catalog_manifest() {
    local action
    for action in "${BOOTSTRAP_ACTION_ORDER[@]}"; do
        printf '%s|%s|%s|%s\n' \
            "$action" \
            "${BOOTSTRAP_ACTION_LABELS[$action]}" \
            "${BOOTSTRAP_ACTION_GROUPS[$action]}" \
            "${BOOTSTRAP_ACTION_DEPS[$action]}" \
            "${BOOTSTRAP_ACTION_PRIVILEGES[$action]}"
    done
}

bootstrap_catalog_hash() {
    local manifest
    manifest="$(bootstrap_catalog_manifest)"
    bootstrap_hash_text "$manifest"
}
