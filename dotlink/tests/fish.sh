#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/repo" "$TMP/home"
(cd "$ROOT" && tar --exclude='./.git' -cf - .) | (cd "$TMP/repo" && tar -xf -)
export HOME="$TMP/home" DOTLINK_HOME="$TMP/home" DOTLINK_REPO_ROOT="$TMP/repo"
export XDG_CONFIG_HOME="$TMP/xdg space"
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
printf 'DOTLINK_PROFILE_MODULES=(fish)\n' > "$TMP/repo/profiles/fish-test.sh"
# Fresh installation, custom XDG, exact lifecycle output and idempotence.
expect 0 $'fish\n' '' "$CLI" list --profile fish-test
expect 0 "missing"$'\tfish\t'"$TARGET"$'\n' '' "$CLI" status fish
expect 1 "missing"$'\tfish\t'"$TARGET"$'\n' '' "$CLI" verify fish
expect 0 "dotlink: linked $TARGET -> $SRC"$'\n' '' "$CLI" link fish
[ -L "$TARGET" ] && [ "$(readlink "$TARGET")" = "$SRC" ]
[ ! -e "$HOME/.config/fish" ]
expect 0 '' '' "$CLI" link fish
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
    expect 1 '' "dotlink: conflict: refusing to replace $TARGET"$'\n' "$CLI" link fish
    expect 1 "conflict"$'\tfish\t'"$TARGET"$'\n' '' "$CLI" status fish
    expect 1 "conflict"$'\tfish\t'"$TARGET"$'\n' '' "$CLI" verify fish
    expect 1 '' "dotlink: conflict: refusing to unlink $TARGET"$'\n' "$CLI" unlink fish
    [ "$before" = "$(ls -ld "$TARGET")" ]
    if [ "$kind" = directory ]; then rmdir "$TARGET"; else rm "$TARGET"; fi
 done
# A later conflict rolls back only new links, not existing user files.
printf '# second\n' > "${SRC%/*}/zz-conflict.fish"
printf 'foreign\n' > "${TARGET%/*}/zz-conflict.fish"
expect 1 "dotlink: linked $TARGET -> $SRC"$'\n' "dotlink: conflict: refusing to replace ${TARGET%/*}/zz-conflict.fish"$'\n' "$CLI" link fish
[ ! -L "$TARGET" ]
grep -qx foreign "${TARGET%/*}/zz-conflict.fish"
rm "${SRC%/*}/zz-conflict.fish" "${TARGET%/*}/zz-conflict.fish"
# No config.fish, functions or mutable files from the source are selected.
printf 'ignored\n' > "$TMP/repo/fish/.config/fish/config.fish"
# Empty and unset XDG both use the isolated HOME.
for mode in empty unset; do
    if [ "$mode" = empty ]; then export XDG_CONFIG_HOME=''; else unset XDG_CONFIG_HOME; fi
    TARGET="$HOME/.config/fish/conf.d/dotfiles.fish"
    expect 0 "dotlink: linked $TARGET -> $SRC"$'\n' '' "$CLI" link fish
    [ ! -e "$HOME/.config/fish/config.fish" ]
    expect 0 '' '' "$CLI" verify fish
    expect 0 "dotlink: unlinked $TARGET"$'\n' '' "$CLI" unlink fish
 done
# Relative XDG is invalid, never interpreted relative to the working directory.
export XDG_CONFIG_HOME=relative
expect 1 '' $'dotlink: XDG_CONFIG_HOME must be an absolute path\n' "$CLI" link fish
printf 'fish tests passed\n'
