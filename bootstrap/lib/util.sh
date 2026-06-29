#!/usr/bin/env bash

set -euo pipefail

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

bootstrap_effective_user() {
    if [ -n "${BOOTSTRAP_TEST_USER:-}" ]; then
        printf '%s\n' "$BOOTSTRAP_TEST_USER"
        return 0
    fi

    if [ -n "${USER:-}" ]; then
        printf '%s\n' "$USER"
        return 0
    fi

    id -un
}

bootstrap_effective_uid() {
    if [ -n "${BOOTSTRAP_TEST_UID:-}" ]; then
        printf '%s\n' "$BOOTSTRAP_TEST_UID"
        return 0
    fi

    id -u
}

bootstrap_target_user() {
    if [ "$(bootstrap_effective_uid)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
        printf '%s\n' "$SUDO_USER"
        return 0
    fi

    bootstrap_effective_user
}

bootstrap_home_for_user() {
    local target_user="$1"
    local home_dir=""

    if [ -z "$target_user" ]; then
        printf 'Unable to resolve home for an empty user name\n' >&2
        return 1
    fi

    if command_exists getent; then
        home_dir="$(getent passwd "$target_user" | awk -F: 'NR==1 {print $6}')"
        if [ -n "$home_dir" ]; then
            printf '%s\n' "$home_dir"
            return 0
        fi
    fi

    case "$target_user" in
        *[!A-Za-z0-9._-]*) ;;
        *)
            home_dir="$(eval "printf '%s\n' ~${target_user}" 2>/dev/null || true)"
            if [ -n "$home_dir" ] && [ "$home_dir" != "~$target_user" ]; then
                printf '%s\n' "$home_dir"
                return 0
            fi
            ;;
    esac

    if [ "$target_user" = "${USER:-}" ] && [ -n "${HOME:-}" ]; then
        printf '%s\n' "$HOME"
        return 0
    fi

    if [ "$target_user" = root ]; then
        printf '/root\n'
        return 0
    fi

    printf 'Unable to resolve home for %s without getent\n' "$target_user" >&2
    return 1
}

bootstrap_target_home() {
    local target_user
    target_user="$(bootstrap_target_user)"
    bootstrap_home_for_user "$target_user"
}

bootstrap_root_owned_action_allowed() {
    local action="$1"
    local -a allowed_actions=()

    bootstrap_split_csv_into_array "${BOOTSTRAP_ROOT_OWNED_ACTIONS:-}" allowed_actions
    bootstrap_array_contains all "${allowed_actions[@]}" || bootstrap_array_contains "$action" "${allowed_actions[@]}"
}

bootstrap_user_action_requires_root_refusal() {
    local action="$1"
    local target_user="${2:-$(bootstrap_target_user)}"

    [ "$(bootstrap_effective_uid)" -eq 0 ] || return 1

    if [ -n "$target_user" ] && [ "$target_user" != root ]; then
        return 1
    fi

    bootstrap_root_owned_action_allowed "$action" && return 1
    return 0
}

bootstrap_execution_context() {
    local uid
    uid="$(bootstrap_effective_uid)"

    if [ "$uid" -eq 0 ]; then
        if [ -n "${SUDO_USER:-}" ]; then
            printf 'root-via-sudo'
        else
            printf 'root-shell'
        fi
        return 0
    fi

    if [ -n "${SUDO_USER:-}" ]; then
        printf 'sudo-session'
    else
        printf 'user-shell'
    fi
}

bootstrap_prompt_yes_no() {
    local prompt="$1"
    local answer=""

    if [ -n "${BOOTSTRAP_AUTO_CONFIRM:-}" ]; then
        case "${BOOTSTRAP_AUTO_CONFIRM}" in
            1|yes|YES|true|TRUE|y|Y) return 0 ;;
        esac
    fi

    if [ ! -t 0 ] && [ ! -t 1 ]; then
        return 1
    fi

    printf '%s [y/N]: ' "$prompt" >&2
    read -r answer < /dev/tty || read -r answer || return 1
    case "$answer" in
        y|Y|yes|YES) return 0 ;;
    esac

    return 1
}

bootstrap_json_bool() {
    case "${1:-false}" in
        1|true|TRUE|yes|YES|y|Y) printf 'true\n' ;;
        *) printf 'false\n' ;;
    esac
}

bootstrap_split_csv_into_array() {
    local csv="${1:-}"
    local array_name="$2"
    local -a values=()

    if [ -n "$csv" ]; then
        IFS=, read -r -a values <<<"$csv"
    fi

    if [ -n "${BASH_VERSION:-}" ]; then
        local -n target_ref="$array_name"
        target_ref=("${values[@]}")
        return 0
    fi

    printf '%s\n' "bootstrap_split_csv_into_array requires bash"
    return 1
}

bootstrap_array_contains() {
    local needle="$1"
    shift

    local item
    for item in "$@"; do
        if [ "$item" = "$needle" ]; then
            return 0
        fi
    done

    return 1
}

bootstrap_join_csv() {
    local joined=""
    local item

    for item in "$@"; do
        if [ -z "$joined" ]; then
            joined="$item"
        else
            joined="$joined,$item"
        fi
    done

    printf '%s\n' "$joined"
}

bootstrap_json_quote() {
    python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"
}

bootstrap_join_json_array() {
    local json=""
    local item

    for item in "$@"; do
        if [ -z "$json" ]; then
            json="$(bootstrap_json_quote "$item")"
        else
            json="$json,$(bootstrap_json_quote "$item")"
        fi
    done

    printf '[%s]' "$json"
}

bootstrap_hash_text() {
    local text="$1"
    local hash

    if command_exists sha256sum; then
        read -r hash _ <<EOF
$(printf '%s' "$text" | sha256sum)
EOF
        printf '%s\n' "$hash"
        return 0
    fi

    if command_exists shasum; then
        read -r hash _ <<EOF
$(printf '%s' "$text" | shasum -a 256)
EOF
        printf '%s\n' "$hash"
        return 0
    fi

    python3 - "$text" <<'PY'
import hashlib, sys
print(hashlib.sha256(sys.argv[1].encode()).hexdigest())
PY
}
