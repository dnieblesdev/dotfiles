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

bootstrap_state_signature_file() {
    printf '%s/bootstrap-secret\n' "$(bootstrap_state_dir)"
}

bootstrap_state_is_current() {
    local expected_hash="$1"
    local expected_target_user="$2"
    local expected_target_home="$3"
    local expected_effective_user="$4"
    local expected_execution_context="$5"
    local expected_frontend="$6"
    local state_file
    local signature_file
    state_file="$(bootstrap_state_file)"
    signature_file="$(bootstrap_state_signature_file)"

    python3 - "$state_file" "$signature_file" "$expected_hash" "$expected_target_user" "$expected_target_home" "$expected_effective_user" "$expected_execution_context" "$expected_frontend" <<'PY'
import json, os, sys
import hmac
import hashlib

state_file = sys.argv[1]
signature_file = sys.argv[2]
expected_hash = sys.argv[3]
expected_context = {
    'target_user': sys.argv[4],
    'target_home': sys.argv[5],
    'effective_user': sys.argv[6],
    'execution_context': sys.argv[7],
    'frontend': sys.argv[8],
}

def fail(reason):
    print(f'provenance:{reason}', file=sys.stderr)
    raise SystemExit(1)

try:
    with open(state_file, 'r', encoding='utf-8') as fh:
        data = json.load(fh)
except FileNotFoundError:
    fail('state_file:missing')
except Exception:
    fail('state_file:unreadable')

try:
    with open(signature_file, 'r', encoding='utf-8') as fh:
        secret = fh.read().strip()
except Exception:
    fail('signature_file:unreadable')

if not secret:
    fail('signature:empty')

signature = data.get('signature', '')
if not signature:
    fail('signature:missing')

payload = dict(data)
payload.pop('signature', None)
canonical = json.dumps(payload, indent=2, separators=(', ', ': '), ensure_ascii=False)
expected_signature = hmac.new(secret.encode('utf-8'), canonical.encode('utf-8'), hashlib.sha256).hexdigest()

if signature != expected_signature:
    fail('signature:mismatch')

if data.get('schema_version') != 1:
    fail('schema_version:incompatible')

if data.get('catalog_hash') != expected_hash:
    fail('catalog_hash:mismatch')

context = data.get('context', {})
if not isinstance(context, dict):
    fail('context:invalid')

for key, expected in expected_context.items():
    actual = context.get(key, '')
    if actual != expected:
        fail(f'{key}:{expected}:{actual}')

raise SystemExit(0)
PY
}

bootstrap_state_completed_actions() {
    local expected_hash="$1"
    local expected_target_user="$2"
    local expected_target_home="$3"
    local expected_effective_user="$4"
    local expected_execution_context="$5"
    local expected_frontend="$6"
    local state_file
    local signature_file
    state_file="$(bootstrap_state_file)"
    signature_file="$(bootstrap_state_signature_file)"

    python3 - "$state_file" "$signature_file" "$expected_hash" "$expected_target_user" "$expected_target_home" "$expected_effective_user" "$expected_execution_context" "$expected_frontend" <<'PY'
import json, sys
import hmac
import hashlib

state_file = sys.argv[1]
signature_file = sys.argv[2]
expected_hash = sys.argv[3]
expected_context = {
    'target_user': sys.argv[4],
    'target_home': sys.argv[5],
    'effective_user': sys.argv[6],
    'execution_context': sys.argv[7],
    'frontend': sys.argv[8],
}

def fail(message):
    print(message, file=sys.stderr)
    raise SystemExit(1)

try:
    with open(state_file, 'r', encoding='utf-8') as fh:
        data = json.load(fh)
except FileNotFoundError:
    fail('Saved bootstrap state file is missing')
except Exception as exc:
    fail(f'Saved bootstrap state file could not be parsed: {exc}')

if not isinstance(data, dict):
    fail('Saved bootstrap state is invalid')

try:
    with open(signature_file, 'r', encoding='utf-8') as fh:
        secret = fh.read().strip()
except Exception as exc:
    fail(f'Saved bootstrap secret could not be loaded: {exc}')

if not secret:
    fail('Saved bootstrap secret is empty')

signature = data.get('signature', '')
if not signature:
    fail('Saved bootstrap state is missing a signature')

payload = dict(data)
payload.pop('signature', None)
canonical = json.dumps(payload, indent=2, separators=(', ', ': '), ensure_ascii=False)
expected_signature = hmac.new(secret.encode('utf-8'), canonical.encode('utf-8'), hashlib.sha256).hexdigest()

if signature != expected_signature:
    fail('Saved bootstrap state signature does not match')

if data.get('schema_version') != 1:
    fail('Saved bootstrap state schema version is incompatible')

if data.get('catalog_hash') != expected_hash:
    fail('Saved bootstrap state catalog hash does not match')

context = data.get('context', {})
if not isinstance(context, dict):
    fail('Saved bootstrap state context is invalid')

for key, expected in expected_context.items():
    actual = context.get(key, '')
    if actual != expected:
        fail(f'Saved bootstrap state context does not match: field={key} expected={expected!r} actual={actual!r}')

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
    local signature_file
    state_file="$(bootstrap_state_file)"
    signature_file="$(bootstrap_state_signature_file)"

    mkdir -p "$(bootstrap_state_dir)"
    chmod 700 "$(bootstrap_state_dir)"

    local secret payload
    local context_target_user context_target_home context_effective_user context_execution_context context_frontend
    secret="$(bootstrap_integrity_load_secret)"
    context_target_user="${BOOTSTRAP_PLAN_CONTEXT_TARGET_USER:-}"
    [ -n "$context_target_user" ] || context_target_user="$(bootstrap_target_user)"
    context_target_home="${BOOTSTRAP_PLAN_CONTEXT_TARGET_HOME:-}"
    [ -n "$context_target_home" ] || context_target_home="$(bootstrap_target_home)"
    context_effective_user="${BOOTSTRAP_PLAN_CONTEXT_EFFECTIVE_USER:-}"
    [ -n "$context_effective_user" ] || context_effective_user="$(bootstrap_effective_user)"
    context_execution_context="${BOOTSTRAP_PLAN_CONTEXT_EXECUTION:-}"
    [ -n "$context_execution_context" ] || context_execution_context="$(bootstrap_execution_context)"
    context_frontend="${BOOTSTRAP_PLAN_CONTEXT_FRONTEND:-}"
    [ -n "$context_frontend" ] || context_frontend="${BOOTSTRAP_FRONTEND_MODE:-unknown}"

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

    payload="$(cat <<EOF
{
  "schema_version": ${BOOTSTRAP_SCHEMA_VERSION},
  "catalog_version": ${BOOTSTRAP_CATALOG_VERSION},
  "catalog_hash": $(bootstrap_json_quote "$catalog_hash"),
  "updated_at": $(bootstrap_json_quote "$updated_at"),
  "last_status": $(bootstrap_json_quote "$status"),
  "context": {
    "target_user": $(bootstrap_json_quote "$context_target_user"),
    "target_home": $(bootstrap_json_quote "$context_target_home"),
    "effective_user": $(bootstrap_json_quote "$context_effective_user"),
    "execution_context": $(bootstrap_json_quote "$context_execution_context"),
    "frontend": $(bootstrap_json_quote "$context_frontend")
  },
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
)"

    printf '%s' "$payload" | bootstrap_json_sign_canonical "$secret" >"$state_file"
}
