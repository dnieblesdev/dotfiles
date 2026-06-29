#!/usr/bin/env bash

set -euo pipefail

command_exists() {
    command -v "$1" >/dev/null 2>&1
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
