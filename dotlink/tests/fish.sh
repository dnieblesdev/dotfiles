#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
if [ -z "${FISH_MAPPING_TEST_MODE:-}" ]; then
    for mode in explicit legacy; do
        printf 'fish mapping mode: %s\n' "$mode"
        FISH_MAPPING_TEST_MODE="$mode" bash "$0"
    done
    bash "$ROOT/dotlink/tests/fish-mise.sh"
    printf 'fish tests passed\n'
    exit 0
fi
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/repo" "$TMP/home"
(cd "$ROOT" && tar --exclude='./.git' -cf - .) | (cd "$TMP/repo" && tar -xf -)
export HOME="$TMP/home" DOTLINK_HOME="$TMP/home" DOTLINK_REPO_ROOT="$TMP/repo"
export XDG_CONFIG_HOME="$TMP/xdg space"
if [ "$FISH_MAPPING_TEST_MODE" = legacy ]; then
    python3 - "$TMP/repo/dotlink/modules.conf" <<'PYTEST'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
start = text.index('[module fish]\n')
end = text.find('[module ', start + 1)
path.write_text(text[:start] + (text[end:] if end != -1 else ''))
PYTEST
fi
CLI="$TMP/repo/bin/dotlink"
SRC="$TMP/repo/fish/.config/fish/conf.d/dotfiles.fish"
TARGET="$XDG_CONFIG_HOME/fish/conf.d/dotfiles.fish"
expect() {
    local code="$1" out="$2" err="$3" actual=0
    shift 3
    "$@" >"$TMP/out" 2>"$TMP/err" || actual=$?
    [ "$actual" = "$code" ]
    printf '%s' "$out" >"$TMP/expected"
    cmp "$TMP/expected" "$TMP/out"
    printf '%s' "$err" >"$TMP/expected"
    cmp "$TMP/expected" "$TMP/err"
}
created_summary=$'dotlink: summary: created=1 unchanged=0 failed=0\n'
unchanged_summary=$'dotlink: summary: created=0 unchanged=1 failed=0\n'
failed_summary=$'dotlink: summary: created=0 unchanged=0 failed=1\n'
mixed_summary=$'dotlink: summary: created=1 unchanged=0 failed=1\n'
printf 'DOTLINK_PROFILE_MODULES=(fish)\n' > "$TMP/repo/profiles/fish-test.sh"
# Fresh installation, custom XDG, exact lifecycle output and idempotence.
expect 0 $'fish\n' '' "$CLI" list --profile fish-test
expect 0 "missing"$'\tfish\t'"$TARGET"$'\n' '' "$CLI" status fish
expect 1 "missing"$'\tfish\t'"$TARGET"$'\n' '' "$CLI" verify fish
expect 0 "dotlink: linked $TARGET -> $SRC"$'\n'"$created_summary" '' "$CLI" link fish
[ -L "$TARGET" ] && [ "$(readlink "$TARGET")" = "$SRC" ]
[ ! -e "$HOME/.config/fish" ]
expect 0 "$unchanged_summary" '' "$CLI" link fish
expect 0 "linked"$'\tfish\t'"$TARGET"$'\n' '' "$CLI" status fish
expect 0 '' '' "$CLI" verify fish
# Existing config and neighboring snippets remain user-owned.
printf 'user config\n' > "$XDG_CONFIG_HOME/fish/config.fish"
printf 'neighbor\n' > "$XDG_CONFIG_HOME/fish/conf.d/local.fish"
expect 0 "dotlink: unlinked $TARGET"$'\n' '' "$CLI" unlink fish
[ ! -L "$TARGET" ]
grep -qx 'user config' "$XDG_CONFIG_HOME/fish/config.fish"
grep -qx neighbor "$XDG_CONFIG_HOME/fish/conf.d/local.fish"
# Foreign regular files, directories, links (including broken) are never adopted.
for kind in file directory symlink broken; do
    case "$kind" in
        file) printf 'foreign\n' > "$TARGET" ;;
        directory) mkdir "$TARGET" ;;
        symlink) ln -s ../config.fish "$TARGET" ;;
        broken) ln -s "$TMP/absent" "$TARGET" ;;
    esac
    before="$(ls -ld "$TARGET")"
    expect 1 "$failed_summary" "dotlink: conflict: refusing to replace $TARGET"$'\n' "$CLI" link fish
    expect 1 "conflict"$'\tfish\t'"$TARGET"$'\n' '' "$CLI" status fish
    expect 1 "conflict"$'\tfish\t'"$TARGET"$'\n' '' "$CLI" verify fish
    expect 1 '' "dotlink: conflict: refusing to unlink $TARGET"$'\n' "$CLI" unlink fish
    [ "$before" = "$(ls -ld "$TARGET")" ]
    if [ "$kind" = directory ]; then rmdir "$TARGET"; else rm "$TARGET"; fi
 done
# A later conflict preserves earlier successes and leaves foreign files unchanged.
cp "$TMP/repo/dotlink/modules.conf" "$TMP/modules.conf"
if [ "$FISH_MAPPING_TEST_MODE" = explicit ]; then
    python3 - "$TMP/repo/dotlink/modules.conf" <<'PYTEST'
from pathlib import Path
import sys
path = Path(sys.argv[1])
block = '[link]\nsource = .config/fish/conf.d/zz-conflict.fish\ntarget = fish/conf.d/zz-conflict.fish\nbase = xdg_config\n\n'
text = path.read_text()
anchor = '[module fish]\n'
assert text.count(anchor) == 1
path.write_text(text.replace(anchor, anchor + block))
PYTEST
fi
printf '# second\n' > "${SRC%/*}/zz-conflict.fish"
printf 'foreign\n' > "${TARGET%/*}/zz-conflict.fish"
expect 1 "dotlink: linked $TARGET -> $SRC"$'\n'"$mixed_summary" "dotlink: conflict: refusing to replace ${TARGET%/*}/zz-conflict.fish"$'\n' "$CLI" link fish
[ -L "$TARGET" ]
grep -qx foreign "${TARGET%/*}/zz-conflict.fish"
rm "${SRC%/*}/zz-conflict.fish" "${TARGET%/*}/zz-conflict.fish"
cp "$TMP/modules.conf" "$TMP/repo/dotlink/modules.conf"
# No config.fish, functions or mutable files from the source are selected.
printf 'ignored\n' > "$TMP/repo/fish/.config/fish/config.fish"
# Empty and unset XDG both use the isolated HOME.
for mode in empty unset; do
    if [ "$mode" = empty ]; then export XDG_CONFIG_HOME=''; else unset XDG_CONFIG_HOME; fi
    TARGET="$HOME/.config/fish/conf.d/dotfiles.fish"
    expect 0 "dotlink: linked $TARGET -> $SRC"$'\n'"$created_summary" '' "$CLI" link fish
    [ ! -e "$HOME/.config/fish/config.fish" ]
    expect 0 '' '' "$CLI" verify fish
    expect 0 "dotlink: unlinked $TARGET"$'\n' '' "$CLI" unlink fish
 done
# Relative XDG is invalid, never interpreted relative to the working directory.
export XDG_CONFIG_HOME=relative
if [ "$FISH_MAPPING_TEST_MODE" = explicit ]; then
    expected_err=$'dotlink: mapping base must be an absolute path: relative\n'
else
    expected_err=$'dotlink: XDG_CONFIG_HOME must be an absolute path\n'
fi
expect 1 "$failed_summary" "$expected_err" "$CLI" link fish

# Fish rejects every symbolic-link component before examining or creating targets.
# This includes valid and broken links at XDG_CONFIG_HOME and below it.
for kind in valid broken; do
    for component in xdg fish conf.d; do
        rm -rf "$TMP/guard"
        mkdir -p "$TMP/guard/real/fish/conf.d" "$TMP/guard/outside"
        if [ "$kind" = valid ]; then
            link_dest="$TMP/guard/outside"
        else
            link_dest="$TMP/guard/does-not-exist"
        fi
        case "$component" in
            xdg)
                ln -s "$link_dest" "$TMP/guard/alias"
                export XDG_CONFIG_HOME="$TMP/guard/alias"
                ;;
            fish)
                mkdir -p "$TMP/guard/xdg"
                ln -s "$link_dest" "$TMP/guard/xdg/fish"
                export XDG_CONFIG_HOME="$TMP/guard/xdg"
                ;;
            conf.d)
                mkdir -p "$TMP/guard/xdg/fish"
                ln -s "$link_dest" "$TMP/guard/xdg/fish/conf.d"
                export XDG_CONFIG_HOME="$TMP/guard/xdg"
                ;;
        esac
        guarded="$XDG_CONFIG_HOME"
        [ "$component" = xdg ] || guarded="$guarded/fish"
        [ "$component" != conf.d ] || guarded="$guarded/conf.d"
        printf -v expected_err 'dotlink: conflict: parent is not a real directory: %s\n' "$guarded"
        expect 1 "$failed_summary" "$expected_err" "$CLI" link fish
        [ ! -e "$TMP/guard/outside/dotfiles.fish" ] && [ ! -L "$TMP/guard/outside/dotfiles.fish" ]
        [ -L "$guarded" ]
    done
done

# A symlink in a higher XDG ancestor is also rejected without touching its destination.
rm -rf "$TMP/guard"
mkdir -p "$TMP/guard/real/xdg" "$TMP/guard/outside"
ln -s "$TMP/guard/real" "$TMP/guard/ancestor"
export XDG_CONFIG_HOME="$TMP/guard/ancestor/xdg"
printf -v expected_err 'dotlink: conflict: parent is not a real directory: %s\n' "$TMP/guard/ancestor"
expect 1 "$failed_summary" "$expected_err" "$CLI" link fish
[ ! -e "$TMP/guard/real/xdg/fish" ]

# Existing links are rejected too when reached through a symbolic ancestor.
rm -rf "$TMP/guard"
mkdir -p "$TMP/guard/real/xdg/fish/conf.d"
export XDG_CONFIG_HOME="$TMP/guard/real/xdg"
TARGET="$XDG_CONFIG_HOME/fish/conf.d/dotfiles.fish"
expect 0 "dotlink: linked $TARGET -> $SRC"$'\n'"$created_summary" '' "$CLI" link fish
ln -s "$TMP/guard/real/xdg" "$TMP/guard/alias"
export XDG_CONFIG_HOME="$TMP/guard/alias"
printf -v expected_err 'dotlink: conflict: parent is not a real directory: %s\n' "$TMP/guard/alias"
expect 1 "$failed_summary" "$expected_err" "$CLI" link fish
[ -L "$TMP/guard/real/xdg/fish/conf.d/dotfiles.fish" ]

# A Fish ancestor failure preserves an earlier Bash success.
rm -rf "$TMP/guard" "$HOME/.bashrc"
mkdir -p "$TMP/guard/outside"
ln -s "$TMP/guard/outside" "$TMP/guard/alias"
export XDG_CONFIG_HOME="$TMP/guard/alias"
printf -v expected_err 'dotlink: conflict: parent is not a real directory: %s\n' "$TMP/guard/alias"
expect 1 "dotlink: linked $HOME/.bashrc -> $TMP/repo/bash/.bashrc"$'\n'"$mixed_summary" "$expected_err" "$CLI" link bash fish
[ -L "$HOME/.bashrc" ]
[ ! -e "$TMP/guard/outside/fish" ]

# Ordinary directories remain valid, including creation of missing descendants.
rm -rf "$TMP/guard"
mkdir -p "$TMP/guard/ordinary"
export XDG_CONFIG_HOME="$TMP/guard/ordinary/new/xdg"
TARGET="$XDG_CONFIG_HOME/fish/conf.d/dotfiles.fish"
expect 0 "dotlink: linked $TARGET -> $SRC"$'\n'"$created_summary" '' "$CLI" link fish
expect 0 "$unchanged_summary" '' "$CLI" link fish
expect 0 '' '' "$CLI" verify fish
[ -L "$TARGET" ]

# Dot and dot-dot components are ambiguous and are rejected, not normalized.
export XDG_CONFIG_HOME="$TMP/guard/ordinary/./xdg"
expect 1 "$failed_summary" $'dotlink: Fish destination may not contain . or .. components\n' "$CLI" link fish
export XDG_CONFIG_HOME="$TMP/guard/ordinary/../other"
expect 1 "$failed_summary" $'dotlink: Fish destination may not contain . or .. components\n' "$CLI" link fish
# zoxide activation is isolated from the user's Fish configuration and binaries.
FISH_BIN="$(command -v fish)" || { printf 'fish is required for Fish tests\n' >&2; exit 1; }
mkdir -p "$TMP/zoxide-bin" "$TMP/no-zoxide-bin"
export ZOXIDE_CALLS="$TMP/zoxide-calls"
cat > "$TMP/zoxide-bin/zoxide" <<'MOCK'
#!/bin/sh
n=0
[ ! -f "$ZOXIDE_CALLS" ] || read n < "$ZOXIDE_CALLS"
n=$((n + 1))
printf '%s\n' "$n" > "$ZOXIDE_CALLS"
printf 'function __zoxide_z; end\n'
MOCK
chmod +x "$TMP/zoxide-bin/zoxide"
assert_fish() {
    local expected_out="$1" expected_err="$2" code="$3" actual=0
    shift 3
    "$@" >"$TMP/fish-out" 2>"$TMP/fish-err" || actual=$?
    [ "$actual" = "$code" ]
    printf '%s' "$expected_out" > "$TMP/fish-expected"
    cmp "$TMP/fish-expected" "$TMP/fish-out"
    printf '%s' "$expected_err" > "$TMP/fish-expected"
    cmp "$TMP/fish-expected" "$TMP/fish-err"
}
rm -f "$ZOXIDE_CALLS"
assert_fish $'initialized\n' '' 0 env PATH="$TMP/zoxide-bin" HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg space" \
    "$FISH_BIN" -N -c "source '$SRC'; source '$SRC'; functions -q __zoxide_z; and echo initialized"
[ "$(<"$ZOXIDE_CALLS")" = 1 ]
rm -f "$ZOXIDE_CALLS"
assert_fish $'preinitialized\n' '' 0 env PATH="$TMP/zoxide-bin" HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg space" \
    "$FISH_BIN" -N -c "function __zoxide_z; end; source '$SRC'; echo preinitialized"
[ ! -e "$ZOXIDE_CALLS" ]
assert_fish $'absent\n' '' 0 env PATH="$TMP/no-zoxide-bin" HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg space" \
    "$FISH_BIN" -N -c "source '$SRC'; functions -q __zoxide_z; or echo absent"

printf 'fish %s lifecycle passed\n' "$FISH_MAPPING_TEST_MODE"
