#!/usr/bin/env bash

set -euo pipefail

BOOTSTRAP_SCHEMA_VERSION=1
BOOTSTRAP_CATALOG_VERSION=1

BOOTSTRAP_ACTION_ORDER=(
    system-packages
    homebrew
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
    [homebrew]="Homebrew bootstrap"
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
    [homebrew]="brew"
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
    [homebrew]="system-packages"
    [brew-tools]="homebrew"
    [dotfiles-clone]="system-packages"
    [dotfiles-backup]="dotfiles-clone"
    [dotfiles-link]="dotfiles-clone dotfiles-backup"
    [runtime-nvm]="system-packages"
    [runtime-uv]="system-packages"
    [runtime-rustup]="system-packages"
)

bootstrap_action_known() {
    local action="$1"

    case "$action" in
        system-packages|homebrew|brew-tools|dotfiles-clone|dotfiles-backup|dotfiles-link|runtime-nvm|runtime-uv|runtime-rustup)
            return 0
            ;;
    esac

    return 1
}

bootstrap_action_deps_array() {
    local action="$1"
    local array_name="$2"
    local deps_value="${BOOTSTRAP_ACTION_DEPS[$action]:-}"
    local -a dep_items=()

    if [ -n "$deps_value" ]; then
        IFS=' ' read -r -a dep_items <<<"$deps_value"
    fi

    local -n target_ref="$array_name"
    target_ref=("${dep_items[@]}")
}

bootstrap_catalog_manifest() {
    local action
    for action in "${BOOTSTRAP_ACTION_ORDER[@]}"; do
        printf '%s|%s|%s|%s\n' \
            "$action" \
            "${BOOTSTRAP_ACTION_LABELS[$action]}" \
            "${BOOTSTRAP_ACTION_GROUPS[$action]}" \
            "${BOOTSTRAP_ACTION_DEPS[$action]}"
    done
}

bootstrap_catalog_hash() {
    local manifest
    manifest="$(bootstrap_catalog_manifest)"
    bootstrap_hash_text "$manifest"
}
