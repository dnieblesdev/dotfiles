#!/usr/bin/env bash

set -euo pipefail

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

bootstrap_test_mode_enabled() {
    case "${BOOTSTRAP_TEST_MODE:-}" in
        1|true|TRUE|yes|YES|y|Y)
            return 0
            ;;
    esac

    return 1
}

bootstrap_test_mode_target_user() {
    if bootstrap_test_mode_enabled && [ -n "${BOOTSTRAP_TARGET_USER:-}" ]; then
        printf '%s\n' "$BOOTSTRAP_TARGET_USER"
        return 0
    fi

    return 1
}

bootstrap_test_mode_target_home() {
    if bootstrap_test_mode_enabled && [ -n "${BOOTSTRAP_TARGET_HOME:-}" ]; then
        printf '%s\n' "$BOOTSTRAP_TARGET_HOME"
        return 0
    fi

    return 1
}

bootstrap_path_owner_uid() {
    local path="$1"

    python3 - "$path" <<'PY'
import os, sys

try:
    print(os.stat(sys.argv[1]).st_uid)
except FileNotFoundError:
    raise SystemExit(1)
except Exception:
    raise SystemExit(1)
PY
}

bootstrap_process_uid() {
    id -u
}

bootstrap_process_user() {
    id -un
}

bootstrap_effective_user() {
    bootstrap_process_user
}

bootstrap_effective_uid() {
    bootstrap_process_uid
}

bootstrap_sudo_loginuid() {
    python3 - <<'PY'
import os, sys

try:
    with open('/proc/self/loginuid', 'r', encoding='utf-8') as fh:
        value = fh.read().strip()
except Exception:
    raise SystemExit(1)

if not value or value == '4294967295':
    raise SystemExit(1)

print(value)
PY
}

bootstrap_process_has_sudo_ancestor() {
    python3 - <<'PY'
import os, sys

def process_name(pid):
    try:
        with open(f'/proc/{pid}/comm', 'r', encoding='utf-8') as fh:
            return fh.read().strip()
    except Exception:
        return ''

def process_cmd0(pid):
    try:
        with open(f'/proc/{pid}/cmdline', 'rb') as fh:
            raw = fh.read().split(b'\0', 1)[0]
    except Exception:
        return ''
    if not raw:
        return ''
    return os.path.basename(raw.decode('utf-8', 'ignore'))

pid = os.getpid()
seen = 0
while pid > 1 and seen < 32:
    if pid != os.getpid():
        name = process_name(pid)
        if name.startswith('sudo') or name == 'sudoedit':
            raise SystemExit(0)

        cmd0 = process_cmd0(pid)
        if cmd0.startswith('sudo') or cmd0 == 'sudoedit':
            raise SystemExit(0)

    try:
        with open(f'/proc/{pid}/stat', 'r', encoding='utf-8') as fh:
            parts = fh.read().split()
        ppid = int(parts[3])
    except Exception:
        break

    if ppid <= 1 or ppid == pid:
        break

    pid = ppid
    seen += 1

raise SystemExit(1)
PY
}

bootstrap_sudo_provenance_trusted() {
    local sudo_user="${SUDO_USER:-}"
    local sudo_uid="${SUDO_UID:-}"
    local resolved_uid=""
    local loginuid=""

    if [ -z "$sudo_user" ] || [ -z "$sudo_uid" ]; then
        return 1
    fi

    resolved_uid="$(id -u "$sudo_user" 2>/dev/null || true)"
    if [ -z "$resolved_uid" ] || [ "$resolved_uid" != "$sudo_uid" ]; then
        return 1
    fi

    loginuid="$(bootstrap_sudo_loginuid 2>/dev/null || true)"
    if [ -z "$loginuid" ] || [ "$loginuid" != "$sudo_uid" ]; then
        return 1
    fi

    bootstrap_process_has_sudo_ancestor
}

bootstrap_target_user() {
    local sudo_target_user=""

    if sudo_target_user="$(bootstrap_test_mode_target_user)"; then
        printf '%s\n' "$sudo_target_user"
        return 0
    fi

    if [ "$(bootstrap_effective_uid)" -eq 0 ]; then
        if sudo_target_user="$(bootstrap_sudo_target_user)"; then
            printf '%s\n' "$sudo_target_user"
            return 0
        fi
    fi

    bootstrap_effective_user
}

bootstrap_sudo_target_user() {
    local sudo_user="${SUDO_USER:-}"
    local sudo_uid="${SUDO_UID:-}"
    local resolved_uid=""

    if [ -z "$sudo_user" ] || [ -z "$sudo_uid" ]; then
        return 1
    fi

    resolved_uid="$(id -u "$sudo_user" 2>/dev/null || true)"
    if [ -z "$resolved_uid" ] || [ "$resolved_uid" != "$sudo_uid" ]; then
        return 1
    fi

    if ! bootstrap_sudo_provenance_trusted; then
        return 1
    fi

    printf '%s\n' "$sudo_user"
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

    if target_user="$(bootstrap_test_mode_target_home)"; then
        printf '%s\n' "$target_user"
        return 0
    fi

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
        if bootstrap_sudo_target_user >/dev/null 2>&1; then
            printf 'root-via-sudo'
        else
            printf 'root-shell'
        fi
        return 0
    fi

    if bootstrap_sudo_target_user >/dev/null 2>&1; then
        printf 'sudo-session'
    else
        printf 'user-shell'
    fi
}

bootstrap_prompt_yes_no() {
    local prompt="$1"
    local answer=""

    if bootstrap_test_mode_enabled && [ -n "${BOOTSTRAP_AUTO_CONFIRM:-}" ]; then
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

bootstrap_integrity_secret_file() {
    printf '%s/bootstrap-secret\n' "$(bootstrap_state_dir)"
}

bootstrap_integrity_load_secret() {
    local secret_file secret_dir secret
    secret_file="$(bootstrap_integrity_secret_file)"
    secret_dir="$(bootstrap_state_dir)"

    mkdir -p "$secret_dir"
    chmod 700 "$secret_dir"

    if [ -f "$secret_file" ]; then
        secret="$(python3 - "$secret_file" <<'PY'
import pathlib, sys

text = pathlib.Path(sys.argv[1]).read_text(encoding='utf-8').strip()
if not text:
    raise SystemExit(1)
print(text)
PY
)"
        [ -n "$secret" ] || return 1
        chmod 600 "$secret_file"
        printf '%s\n' "$secret"
        return 0
    fi

    umask 077
    secret="$(python3 <<'PY'
import secrets

print(secrets.token_hex(32))
PY
)"
    printf '%s\n' "$secret" >"$secret_file"
    chmod 600 "$secret_file"
    printf '%s\n' "$secret"
}

bootstrap_integrity_hmac() {
    local secret="$1"

    python3 -c 'import hashlib, hmac, sys; secret = sys.argv[1].encode("utf-8"); payload = sys.stdin.read().encode("utf-8"); print(hmac.new(secret, payload, hashlib.sha256).hexdigest())' "$secret"
}

bootstrap_json_add_signature() {
    local signature="$1"

    python3 - "$signature" <<'PY'
import json
import sys

signature = sys.argv[1]
data = json.load(sys.stdin)
data['signature'] = signature
print(json.dumps(data, indent=2, ensure_ascii=False))
PY
}

bootstrap_json_canonical_signature() {
    local secret="$1"

    python3 -c 'import hashlib, hmac, json, sys; secret = sys.argv[1].encode("utf-8"); data = json.load(sys.stdin); signature = data.pop("signature", "");
if not signature: raise SystemExit(1)
canonical = json.dumps(data, indent=2, separators=(", ", ": "), ensure_ascii=False)
print(hmac.new(secret, canonical.encode("utf-8"), hashlib.sha256).hexdigest())' "$secret"
}

bootstrap_json_sign_canonical() {
    local secret="$1"

    python3 -c 'import hashlib, hmac, json, sys; secret = sys.argv[1].encode("utf-8"); data = json.load(sys.stdin); data.pop("signature", None); canonical = json.dumps(data, indent=2, separators=(", ", ": "), ensure_ascii=False); data["signature"] = hmac.new(secret, canonical.encode("utf-8"), hashlib.sha256).hexdigest(); print(json.dumps(data, indent=2, ensure_ascii=False))' "$secret"
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
