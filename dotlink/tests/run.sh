#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_ROOT="$(mktemp -d)"
TMP_REPO="$TMP_ROOT/repo"

cleanup() {
    rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

# Build a disposable copy of the repository so tests never mutate the source tree.
mkdir -p "$TMP_REPO"
cp -a "$REPO_ROOT"/. "$TMP_REPO"
rm -rf "$TMP_REPO/.git"

export DOTLINK_HOME="$TMP_ROOT/home"
mkdir -p "$DOTLINK_HOME"
export DOTLINK_REPO_ROOT="$TMP_REPO"

BAD_PROFILE="$TMP_REPO/profiles/bad-test.sh"
ROLLBACK_A="$TMP_REPO/config/.config/dotlink-test-a"
ROLLBACK_B="$TMP_REPO/config/.config/dotlink-test-b"

assert_link() {
    local target="$1"
    local expected="$2"
    [ -L "$target" ] || { printf 'expected symlink: %s\n' "$target" >&2; exit 1; }
    [ "$(readlink "$target")" = "$expected" ] || { printf 'unexpected target for %s\n' "$target" >&2; exit 1; }
}

assert_missing() {
    local target="$1"
    [ ! -e "$target" ] && [ ! -L "$target" ] || { printf 'expected missing: %s\n' "$target" >&2; exit 1; }
}

"$TMP_REPO/bin/dotlink" list --profile base > "$TMP_ROOT/list.out"
grep -qx 'bash' "$TMP_ROOT/list.out"
"$TMP_REPO/bin/dotlink" list --profile=base > "$TMP_ROOT/list-equals.out"
grep -qx 'bash' "$TMP_ROOT/list-equals.out"
"$TMP_REPO/bin/dotlink" link --profile base
assert_link "$DOTLINK_HOME/.bashrc" "$TMP_REPO/bash/.bashrc"
assert_link "$DOTLINK_HOME/.gitconfig" "$TMP_REPO/git/.gitconfig"
"$TMP_REPO/bin/dotlink" verify --profile base
"$TMP_REPO/bin/dotlink" status --profile base > "$TMP_ROOT/status.out"
grep -q '^linked' "$TMP_ROOT/status.out"
"$TMP_REPO/bin/dotlink" unlink --profile base
assert_missing "$DOTLINK_HOME/.bashrc"

# Nested config entry link/unlink coverage.
"$TMP_REPO/bin/dotlink" link config
assert_link "$DOTLINK_HOME/.config/starship.toml" "$TMP_REPO/config/.config/starship.toml"
"$TMP_REPO/bin/dotlink" unlink config
assert_missing "$DOTLINK_HOME/.config/starship.toml"

if "$TMP_REPO/bin/dotlink" link bash not-a-module >"$TMP_ROOT/dotlink-unknown-link.out" 2>"$TMP_ROOT/dotlink-unknown-link.err"; then
    printf 'expected unknown explicit module link failure\n' >&2
    exit 1
fi
grep -q 'unknown module: not-a-module' "$TMP_ROOT/dotlink-unknown-link.err"
assert_missing "$DOTLINK_HOME/.bashrc"

if "$TMP_REPO/bin/dotlink" status not-a-module >"$TMP_ROOT/dotlink-unknown-status.out" 2>"$TMP_ROOT/dotlink-unknown-status.err"; then
    printf 'expected unknown explicit module status failure\n' >&2
    exit 1
fi
grep -q 'unknown module: not-a-module' "$TMP_ROOT/dotlink-unknown-status.err"

if "$TMP_REPO/bin/dotlink" verify not-a-module >"$TMP_ROOT/dotlink-unknown-verify.out" 2>"$TMP_ROOT/dotlink-unknown-verify.err"; then
    printf 'expected unknown explicit module verify failure\n' >&2
    exit 1
fi
grep -q 'unknown module: not-a-module' "$TMP_ROOT/dotlink-unknown-verify.err"

if "$TMP_REPO/bin/dotlink" link scripts >"$TMP_ROOT/dotlink-scripts-link.out" 2>"$TMP_ROOT/dotlink-scripts-link.err"; then
    printf 'expected operational scripts directory link rejection\n' >&2
    exit 1
fi
grep -q 'unknown module: scripts' "$TMP_ROOT/dotlink-scripts-link.err"

if "$TMP_REPO/bin/dotlink" status scripts >"$TMP_ROOT/dotlink-scripts-status.out" 2>"$TMP_ROOT/dotlink-scripts-status.err"; then
    printf 'expected operational scripts directory status rejection\n' >&2
    exit 1
fi
grep -q 'unknown module: scripts' "$TMP_ROOT/dotlink-scripts-status.err"

if "$TMP_REPO/bin/dotlink" verify scripts >"$TMP_ROOT/dotlink-scripts-verify.out" 2>"$TMP_ROOT/dotlink-scripts-verify.err"; then
    printf 'expected operational scripts directory verify rejection\n' >&2
    exit 1
fi
grep -q 'unknown module: scripts' "$TMP_ROOT/dotlink-scripts-verify.err"

printf 'local config\n' > "$DOTLINK_HOME/.bashrc"
if "$TMP_REPO/bin/dotlink" link bash >"$TMP_ROOT/dotlink-conflict.out" 2>"$TMP_ROOT/dotlink-conflict.err"; then
    printf 'expected regular-file conflict\n' >&2
    exit 1
fi
grep -q 'conflict' "$TMP_ROOT/dotlink-conflict.err"
rm "$DOTLINK_HOME/.bashrc"

ln -s /tmp/not-owned "$DOTLINK_HOME/.bashrc"
if "$TMP_REPO/bin/dotlink" link bash >"$TMP_ROOT/dotlink-foreign-link.out" 2>"$TMP_ROOT/dotlink-foreign-link.err"; then
    printf 'expected foreign-symlink link conflict\n' >&2
    exit 1
fi
grep -q 'conflict' "$TMP_ROOT/dotlink-foreign-link.err"
[ -L "$DOTLINK_HOME/.bashrc" ] || { printf 'foreign symlink was replaced during link\n' >&2; exit 1; }
[ "$(readlink "$DOTLINK_HOME/.bashrc")" = /tmp/not-owned ] || { printf 'foreign symlink target changed during link\n' >&2; exit 1; }
rm "$DOTLINK_HOME/.bashrc"

ln -s /tmp/not-owned "$DOTLINK_HOME/.bashrc"
if "$TMP_REPO/bin/dotlink" unlink bash >"$TMP_ROOT/dotlink-unlink.out" 2>"$TMP_ROOT/dotlink-unlink.err"; then
    printf 'expected foreign-symlink unlink conflict\n' >&2
    exit 1
fi
[ -L "$DOTLINK_HOME/.bashrc" ] || { printf 'foreign symlink was removed\n' >&2; exit 1; }
rm "$DOTLINK_HOME/.bashrc"

cat > "$BAD_PROFILE" <<'BAD'
DOTLINK_PROFILE_MODULES=(bash)
touch /tmp/dotlink-should-not-run
BAD
if "$TMP_REPO/bin/dotlink" list --profile bad-test >"$TMP_ROOT/dotlink-bad.out" 2>"$TMP_ROOT/dotlink-bad.err"; then
    printf 'expected manifest validation failure\n' >&2
    exit 1
fi
assert_missing /tmp/dotlink-should-not-run

ln -s /tmp/broken-dotlink-target "$DOTLINK_HOME/.bashrc"
if "$TMP_REPO/bin/dotlink" link bash >"$TMP_ROOT/dotlink-broken-link.out" 2>"$TMP_ROOT/dotlink-broken-link.err"; then
    printf 'expected broken-symlink link conflict\n' >&2
    exit 1
fi
grep -q 'conflict' "$TMP_ROOT/dotlink-broken-link.err"
[ -L "$DOTLINK_HOME/.bashrc" ] || { printf 'broken symlink was removed during link\n' >&2; exit 1; }
[ "$(readlink "$DOTLINK_HOME/.bashrc")" = /tmp/broken-dotlink-target ] || { printf 'broken symlink target changed during link\n' >&2; exit 1; }
rm "$DOTLINK_HOME/.bashrc"

"$TMP_REPO/bin/dotlink" link git
rm "$DOTLINK_HOME/.gitconfig"
ln -s /tmp/drifted-dotlink-target "$DOTLINK_HOME/.gitconfig"
if "$TMP_REPO/bin/dotlink" verify git >"$TMP_ROOT/dotlink-drift-verify.out" 2>"$TMP_ROOT/dotlink-drift-verify.err"; then
    printf 'expected drifted verify failure\n' >&2
    exit 1
fi
grep -q '^conflict[[:space:]]\+git[[:space:]]' "$TMP_ROOT/dotlink-drift-verify.out"
rm "$DOTLINK_HOME/.gitconfig"
"$TMP_REPO/bin/dotlink" link git
rm "$DOTLINK_HOME/.gitconfig"
if "$TMP_REPO/bin/dotlink" verify git >"$TMP_ROOT/dotlink-partial-verify.out" 2>"$TMP_ROOT/dotlink-partial-verify.err"; then
    printf 'expected partial verify failure\n' >&2
    exit 1
fi
grep -q '^missing[[:space:]]\+git[[:space:]]' "$TMP_ROOT/dotlink-partial-verify.out"

printf 'one\n' > "$ROLLBACK_A"
printf 'two\n' > "$ROLLBACK_B"
mkdir -p "$DOTLINK_HOME/.config"
printf 'local conflict\n' > "$DOTLINK_HOME/.config/dotlink-test-b"
if "$TMP_REPO/bin/dotlink" link config >"$TMP_ROOT/dotlink-rollback.out" 2>"$TMP_ROOT/dotlink-rollback.err"; then
    printf 'expected config rollback conflict\n' >&2
    exit 1
fi
assert_missing "$DOTLINK_HOME/.config/dotlink-test-a"
[ -f "$DOTLINK_HOME/.config/dotlink-test-b" ] || { printf 'rollback conflict file was removed\n' >&2; exit 1; }
grep -q 'local conflict' "$DOTLINK_HOME/.config/dotlink-test-b"

printf 'dotlink tests passed\n'
