#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FISH="$(command -v fish)" || { printf 'fish is required for Fish mise tests\n' >&2; exit 1; }
MISE="$(command -v mise)" || { printf 'mise is required for Fish mise tests\n' >&2; exit 1; }
SRC="$ROOT/fish/.config/fish/conf.d/dotfiles.fish"
mkdir -p "$TMP/home" "$TMP/config/fish" "$TMP/config/mise" "$TMP/data" "$TMP/cache" "$TMP/state" \
    "$TMP/bin" "$TMP/no-mise-bin" "$TMP/toolA/bin" "$TMP/toolB/bin" "$TMP/A" "$TMP/B" "$TMP/runtime"
: > "$TMP/config/mise/config.toml"
printf '#!/bin/sh\necho A\n' > "$TMP/toolA/bin/node"
printf '#!/bin/sh\necho B\n' > "$TMP/toolB/bin/node"
printf '#!/bin/sh\necho FOREIGN\n' > "$TMP/home/node"
chmod +x "$TMP/toolA/bin/node" "$TMP/toolB/bin/node" "$TMP/home/node"
cat > "$TMP/A/mise.toml" <<EOF
[tools]
node = "path:$TMP/toolA"
[env]
DIAG_PROJECT = "A"
EOF
cat > "$TMP/B/mise.toml" <<EOF
[tools]
node = "path:$TMP/toolB"
[env]
DIAG_PROJECT = "B"
EOF
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/config" XDG_DATA_HOME="$TMP/data" \
    XDG_CACHE_HOME="$TMP/cache" XDG_STATE_HOME="$TMP/state" MISE_OFFLINE=true \
    MISE_AUTO_INSTALL=false MISE_TRUSTED_CONFIG_PATHS="$TMP/A:$TMP/B"
# Never inherit a user's config, mise state, or Fish universal variables.
run_fish() {
    env -i HOME="$HOME" TMPDIR="$TMP/runtime" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" XDG_DATA_HOME="$XDG_DATA_HOME" \
        XDG_CACHE_HOME="$XDG_CACHE_HOME" XDG_STATE_HOME="$XDG_STATE_HOME" XDG_RUNTIME_DIR="$TMP/runtime" \
        MISE_CONFIG_FILE="$TMP/config/mise/config.toml" MISE_DATA_DIR="$TMP/data/mise" MISE_CACHE_DIR="$TMP/cache/mise" \
        MISE_STATE_DIR="$TMP/state/mise" MISE_OFFLINE=true MISE_AUTO_INSTALL=false MISE_TRUSTED_CONFIG_PATHS="$MISE_TRUSTED_CONFIG_PATHS" \
        PATH="${FISH_PATH:-$TMP/bin:/usr/bin:/bin}" REAL_MISE="$MISE" FISH_SRC="$SRC" "$FISH" "$@"
}
fail() { printf 'fish mise test failed: %s\n' "$1" >&2; exit 1; }
assert_output() {
    local expected="$1"; shift
    local actual
    actual="$(run_fish "$@" 2>"$TMP/stderr")" || fail "fish exited nonzero ($*)"
    [ ! -s "$TMP/stderr" ] || { printf 'unexpected stderr:\n' >&2; cat "$TMP/stderr" >&2; fail "$*"; }
    [ "$actual" = "$expected" ] || { printf 'expected:\n%s\nactual:\n%s\n' "$expected" "$actual" >&2; fail "$*"; }
}
# With no mise available, interactive startup is silent, and the one-shot callback is removed.
FISH_PATH="$TMP/no-mise-bin" assert_output 'no-mise:unset' -N -i -c "source '$SRC'; emit fish_prompt; functions -q __dotfiles_mise_activate_on_prompt; and echo callback-left; or printf 'no-mise:%s\\n' (set -q MISE_ACTIVATE_AGGRESSIVE; and echo set; or echo unset)"
unset FISH_PATH
# Noninteractive shells must not schedule activation, even when mise is available.
assert_output 'no-handler' -N -c "source '$SRC'; functions -q __dotfiles_mise_activate_on_prompt; and echo handler; or echo no-handler"

# Regression control: official default activation alone loses PATH precedence to a later startup edit.
assert_output 'FOREIGN:A' -N -i -c "cd '$TMP/A'; source (command mise activate fish | psub); fish_add_path --path --move '$TMP/home'; printf '%s:%s\\n' (command node) \$DIAG_PROJECT"

# Actual mise activation and project selection: first prompt, then A -> B -> A directory hooks.
assert_output $'A:A\nB:B\nA:A' -N -i -c "cd '$TMP/A'; source '$SRC'; emit fish_prompt; if command -q node; printf '%s:%s\\n' (command node) \$DIAG_PROJECT; else echo missing; end; cd '$TMP/B'; if command -q node; printf '%s:%s\\n' (command node) \$DIAG_PROJECT; else echo missing; end; cd '$TMP/A'; if command -q node; printf '%s:%s\\n' (command node) \$DIAG_PROJECT; else echo missing; end"

# A competing PATH update after early activation is repaired by the authorized one-time prompt reactivation.
assert_output 'A:true' -N -i -c "cd '$TMP/A'; source (command mise activate fish | psub); fish_add_path --path --move '$TMP/home'; set -gx MISE_ACTIVATE_AGGRESSIVE false; source '$SRC'; emit fish_prompt; printf '%s:%s\\n' (command node) \$MISE_ACTIVATE_AGGRESSIVE"

# Activation before or after snippet loading remains single-shot; sourcing again cannot add callbacks.
assert_output '1' -N -i -c "cd '$TMP/A'; source '$SRC'; source '$SRC'; functions -q __dotfiles_mise_activate_on_prompt; and echo 1; or echo 0"
assert_output $'A\n0\n1\n1\n1' -N -i -c "cd '$TMP/A'; source (command mise activate fish | psub); source '$SRC'; emit fish_prompt; command node; functions -q __dotfiles_mise_activate_on_prompt; and echo 1; or echo 0; functions -H | string match -r 'PWD __mise_cd_hook' | count; functions -H | string match -r 'fish_preexec __mise_env_eval_2' | count; functions -H | string match -r 'fish_prompt __mise_env_eval_on_prompt' | count"
assert_output $'A\n0\n1\n1\n1' -N -i -c "cd '$TMP/A'; source '$SRC'; source (command mise activate fish | psub); emit fish_prompt; command node; functions -q __dotfiles_mise_activate_on_prompt; and echo 1; or echo 0; functions -H | string match -r 'PWD __mise_cd_hook' | count; functions -H | string match -r 'fish_preexec __mise_env_eval_2' | count; functions -H | string match -r 'fish_prompt __mise_env_eval_on_prompt' | count"
assert_output $'A\n0\n1\n1\n1' -N -i -c "cd '$TMP/A'; source '$SRC'; emit fish_prompt; source '$SRC'; command node; functions -q __dotfiles_mise_activate_on_prompt; and echo 1; or echo 0; functions -H | string match -r 'PWD __mise_cd_hook' | count; functions -H | string match -r 'fish_preexec __mise_env_eval_2' | count; functions -H | string match -r 'fish_prompt __mise_env_eval_on_prompt' | count"
assert_output 'A' -N -l -i -c "cd '$TMP/A'; source '$SRC'; emit fish_prompt; command node"

# Inherited MISE_SHELL alone is not treated as proof that activation hooks exist.
assert_output 'A' -N -i -c "cd '$TMP/A'; set -gx MISE_SHELL fish; source '$SRC'; emit fish_prompt; command node"
printf 'fish mise tests passed (Fish %s; mise %s)\n' "$($FISH --version)" "$($MISE --version)"
