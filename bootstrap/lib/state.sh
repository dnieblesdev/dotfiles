#!/usr/bin/env bash

set -euo pipefail

bootstrap_state_dir() {
    if [ -n "${BOOTSTRAP_STATE_DIR:-}" ]; then
        printf '%s\n' "$BOOTSTRAP_STATE_DIR"
        return 0
    fi

    if [ -n "${BOOTSTRAP_STATE_FILE:-}" ]; then
        printf '%s\n' "${BOOTSTRAP_STATE_FILE%/*}"
        return 0
    fi

    printf '%s/dniebles\n' "${XDG_STATE_HOME:-$HOME/.local/state}"
}

bootstrap_state_file() {
    if [ -n "${BOOTSTRAP_STATE_FILE:-}" ]; then
        printf '%s\n' "$BOOTSTRAP_STATE_FILE"
        return 0
    fi

    printf '%s/bootstrap-state.json\n' "$(bootstrap_state_dir)"
}

bootstrap_state_is_current() {
    local expected_hash="$1"
    local state_file
    state_file="$(bootstrap_state_file)"

    python3 - "$state_file" "$expected_hash" <<'PY'
import json, os, sys

state_file = sys.argv[1]
expected_hash = sys.argv[2]

try:
    with open(state_file, 'r', encoding='utf-8') as fh:
        data = json.load(fh)
except FileNotFoundError:
    raise SystemExit(1)
except Exception:
    raise SystemExit(1)

if data.get('schema_version') != 1:
    raise SystemExit(1)

if data.get('catalog_hash') != expected_hash:
    raise SystemExit(1)

raise SystemExit(0)
PY
}

bootstrap_state_completed_actions() {
    local expected_hash="$1"
    local state_file
    state_file="$(bootstrap_state_file)"

    python3 - "$state_file" "$expected_hash" <<'PY'
import json, sys

state_file = sys.argv[1]
expected_hash = sys.argv[2]

try:
    with open(state_file, 'r', encoding='utf-8') as fh:
        data = json.load(fh)
except Exception:
    raise SystemExit(0)

if data.get('schema_version') != 1:
    raise SystemExit(0)

if data.get('catalog_hash') != expected_hash:
    raise SystemExit(0)

for action in data.get('completed_actions', []):
    print(action)
PY
}

bootstrap_state_write() {
    local catalog_hash="$1"
    local status="$2"
    local failed_action="${3:-}"
    local failed_exit_code="${4:-0}"
    local failed_message="${5:-}"
    local only_csv="${6:-}"
    local skip_csv="${7:-}"
    local force_csv="${8:-}"
    local ordered_csv="${9:-}"
    local execute_csv="${10:-}"
    local completed_csv="${11:-}"
    local state_file
    state_file="$(bootstrap_state_file)"

    mkdir -p "$(bootstrap_state_dir)"

    local updated_at
    updated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    local -a only=()
    local -a skip=()
    local -a force=()
    local -a ordered=()
    local -a execute=()
    local -a completed=()

    bootstrap_split_csv_into_array "$only_csv" only
    bootstrap_split_csv_into_array "$skip_csv" skip
    bootstrap_split_csv_into_array "$force_csv" force
    bootstrap_split_csv_into_array "$ordered_csv" ordered
    bootstrap_split_csv_into_array "$execute_csv" execute
    bootstrap_split_csv_into_array "$completed_csv" completed

    cat >"$state_file" <<EOF
{
  "schema_version": ${BOOTSTRAP_SCHEMA_VERSION},
  "catalog_version": ${BOOTSTRAP_CATALOG_VERSION},
  "catalog_hash": $(bootstrap_json_quote "$catalog_hash"),
  "updated_at": $(bootstrap_json_quote "$updated_at"),
  "last_status": $(bootstrap_json_quote "$status"),
  "selection": {
    "only": $(bootstrap_join_json_array "${only[@]}"),
    "skip": $(bootstrap_join_json_array "${skip[@]}"),
    "force": $(bootstrap_join_json_array "${force[@]}")
  },
  "plan": {
    "ordered": $(bootstrap_join_json_array "${ordered[@]}"),
    "execute": $(bootstrap_join_json_array "${execute[@]}")
  },
  "completed_actions": $(bootstrap_join_json_array "${completed[@]}"),
  "failed_action": $(bootstrap_json_quote "$failed_action"),
  "failed_exit_code": ${failed_exit_code},
  "failed_message": $(bootstrap_json_quote "$failed_message")
}
EOF
}
