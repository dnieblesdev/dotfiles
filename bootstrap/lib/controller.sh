#!/usr/bin/env bash

set -euo pipefail

BOOTSTRAP_CONTROLLER_PROTOCOL_VERSION=1

bootstrap_controller_emit_handshake() {
    cat <<EOF
{
  "protocol_version": ${BOOTSTRAP_CONTROLLER_PROTOCOL_VERSION},
  "status": "ok",
  "shell_contract": "bootstrap-controller",
  "shell_contract_version": ${BOOTSTRAP_CONTROLLER_PROTOCOL_VERSION},
  "bootstrap_schema_version": ${BOOTSTRAP_SCHEMA_VERSION},
  "bootstrap_catalog_version": ${BOOTSTRAP_CATALOG_VERSION},
  "supported_shell_commands": ["list", "plan", "apply"]
}
EOF
}

bootstrap_controller_emit_unsupported() {
    local received_version="$1"

    cat <<EOF
{
  "protocol_version": ${BOOTSTRAP_CONTROLLER_PROTOCOL_VERSION},
  "status": "unsupported",
  "expected_protocol_version": ${BOOTSTRAP_CONTROLLER_PROTOCOL_VERSION},
  "received_protocol_version": ${received_version},
  "error": "controller protocol mismatch"
}
EOF
}

bootstrap_controller_handle_request() {
    local request_json
    local request_protocol
    local request_kind

    request_json="$(cat)"
    if [ -z "$request_json" ]; then
        request_json='{"protocol_version":1,"request":"handshake","client":"bootstrap-controller"}'
    fi

    if ! python3 -c 'import json,sys; json.loads(sys.argv[1])' "$request_json" >/dev/null 2>&1; then
        cat <<EOF
{
  "protocol_version": ${BOOTSTRAP_CONTROLLER_PROTOCOL_VERSION},
  "status": "invalid",
  "error": "request JSON is invalid"
}
EOF
        return 65
    fi

    request_protocol="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("protocol_version", 0))' "$request_json")"

    if [ "$request_protocol" != "$BOOTSTRAP_CONTROLLER_PROTOCOL_VERSION" ]; then
        bootstrap_controller_emit_unsupported "$request_protocol"
        return 64
    fi

    request_kind="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("request", "handshake"))' "$request_json")"

    case "$request_kind" in
        handshake|bootstrap-handshake|version)
            bootstrap_controller_emit_handshake
            ;;
        *)
            cat <<EOF
{
  "protocol_version": ${BOOTSTRAP_CONTROLLER_PROTOCOL_VERSION},
  "status": "unsupported-request",
  "request": $(bootstrap_json_quote "$request_kind"),
  "error": "unsupported controller request"
}
EOF
            return 65
            ;;
    esac
}
