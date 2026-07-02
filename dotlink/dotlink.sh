#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="${DOTLINK_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
DOTLINK_HOME="${DOTLINK_HOME:-$HOME}"

# shellcheck source=manifest.sh
source "$REPO_ROOT/dotlink/manifest.sh"

usage() {
    cat <<'USAGE'
Usage:
  bin/dotlink link [--profile NAME] [MODULE...]
  bin/dotlink list [--profile NAME]
  bin/dotlink status [--profile NAME] [MODULE...]
  bin/dotlink unlink [--profile NAME] [MODULE...]
  bin/dotlink verify [--profile NAME] [MODULE...]

Dotlink manages repository-owned symlinks only. It never installs packages,
runtimes, tools, or OS bootstrap dependencies.
USAGE
}

info() { printf 'dotlink: %s\n' "$1"; }
warn() { printf 'dotlink: %s\n' "$1" >&2; }

real_path() {
    local path="$1"
    if command -v realpath >/dev/null 2>&1 && realpath -m / >/dev/null 2>&1; then
        realpath -m "$path"
    elif command -v python3 >/dev/null 2>&1; then
        python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$path"
    elif command -v readlink >/dev/null 2>&1 && readlink -f / >/dev/null 2>&1; then
        readlink -f "$path"
    else
        # Fallback: normalize leading tilde and follow symlinks manually for existing paths.
        # Non-existent paths are returned with tilde expansion but without . / .. collapse.
        case "$path" in
            ~/*) path="$HOME/${path#~/}" ;;
            '~') path="$HOME" ;;
        esac
        if [ -e "$path" ]; then
            (cd "$path" && pwd) 2>/dev/null || printf '%s\n' "$path"
        else
            printf '%s\n' "$path"
        fi
    fi
}

is_repo_path() {
    local path="$1"
    local resolved_root resolved_path
    resolved_root="$(real_path "$REPO_ROOT")"
    resolved_path="$(real_path "$path")"
    case "$resolved_path" in
        "$resolved_root"|"$resolved_root"/*) return 0 ;;
        *) return 1 ;;
    esac
}

is_owned_symlink() {
    local target="$1"
    local link_target
    [ -L "$target" ] || return 1
    link_target="$(readlink "$target")"
    case "$link_target" in
        /*) is_repo_path "$link_target" ;;
        *) is_repo_path "$(dirname "$target")/$link_target" ;;
    esac
}

link_matches() {
    local src="$1"
    local target="$2"
    local link_target
    [ -L "$target" ] || return 1
    [ -e "$src" ] || return 1
    link_target="$(readlink "$target")"
    if [ "$(real_path "$(dirname "$target")/$link_target")" = "$(real_path "$src")" ]; then
        return 0
    fi
    case "$link_target" in
        /*)
            [ "$(real_path "$link_target")" = "$(real_path "$src")" ]
            ;;
        *)
            return 1
            ;;
    esac
}

collect_module_entries() {
    local module="$1"
    local src_dir="$REPO_ROOT/$module"
    local file dir inner rel_path target_dir

    [ -d "$src_dir" ] || {
        warn "unknown module: $module"
        return 1
    }

    while IFS= read -r -d '' file; do
        printf '%s\t%s\n' "$file" "$DOTLINK_HOME/$(basename "$file")"
    done < <(find "$src_dir" -maxdepth 1 -name '.*' -type f -print0 2>/dev/null | sort -z)

    while IFS= read -r -d '' dir; do
        rel_path="${dir#$src_dir/}"
        target_dir="$DOTLINK_HOME/$rel_path"
        while IFS= read -r -d '' inner; do
            printf '%s\t%s\n' "$inner" "$target_dir/$(basename "$inner")"
        done < <(find "$dir" -mindepth 1 -maxdepth 1 \( -type f -o -type d \) -print0 2>/dev/null | sort -z)
    done < <(find "$src_dir" -mindepth 1 -maxdepth 1 -type d -name '.*' -print0 2>/dev/null | sort -z)
}

resolve_modules() {
    local profile="base"
    local -a explicit=()
    local module

    while [ $# -gt 0 ]; do
        case "$1" in
            --profile)
                [ $# -ge 2 ] || { warn "--profile requires a name"; return 2; }
                profile="$2"
                shift 2
                ;;
            --profile=*)
                profile="${1#--profile=}"
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            --*)
                warn "unknown option: $1"
                return 2
                ;;
            *)
                explicit+=("$1")
                shift
                ;;
        esac
    done

    if [ "${#explicit[@]}" -gt 0 ]; then
        for module in "${explicit[@]}"; do
            if ! dotlink_is_known_module "$REPO_ROOT" "$module"; then
                warn "unknown module: $module"
                return 1
            fi
        done
        printf '%s\n' "${explicit[@]}"
        return 0
    fi

    dotlink_load_profile "$REPO_ROOT" "$profile" || return 1
    printf '%s\n' "${DOTLINK_PROFILE_MODULES[@]}"
}

ensure_parent_dir() {
    local target="$1"
    local parent
    parent="$(dirname "$target")"

    if [ -d "$parent" ] && [ ! -L "$parent" ]; then
        return 0
    fi
    if [ -e "$parent" ] || [ -L "$parent" ]; then
        warn "conflict: parent is not a real directory: $parent"
        return 1
    fi
    mkdir -p "$parent"
}

entry_state() {
    local src="$1"
    local target="$2"

    if [ -L "$target" ]; then
        if link_matches "$src" "$target"; then
            printf 'linked'
        elif is_owned_symlink "$target"; then
            printf 'drift'
        else
            printf 'conflict'
        fi
    elif [ -e "$target" ]; then
        printf 'conflict'
    else
        printf 'missing'
    fi
}

cmd_list() {
    local modules=("$@")
    local module
    for module in "${modules[@]}"; do
        printf '%s\n' "$module"
    done
}

cmd_status() {
    local modules=("$@")
    local module src target state entries rc=0
    for module in "${modules[@]}"; do
        entries="$(collect_module_entries "$module")" || return 1
        while IFS=$'\t' read -r src target; do
            [ -n "$src" ] || continue
            state="$(entry_state "$src" "$target")"
            [ "$state" != conflict ] || rc=1
            printf '%s\t%s\t%s\n' "$state" "$module" "$target"
        done <<< "$entries"
    done
    return "$rc"
}

cmd_verify() {
    local modules=("$@")
    local module src target state entries rc=0
    for module in "${modules[@]}"; do
        entries="$(collect_module_entries "$module")" || return 1
        while IFS=$'\t' read -r src target; do
            [ -n "$src" ] || continue
            state="$(entry_state "$src" "$target")"
            if [ "$state" != linked ]; then
                rc=1
                printf '%s\t%s\t%s\n' "$state" "$module" "$target"
            fi
        done <<< "$entries"
    done
    return "$rc"
}

cmd_unlink() {
    local modules=("$@")
    local module src target state entries rc=0
    for module in "${modules[@]}"; do
        entries="$(collect_module_entries "$module")" || return 1
        while IFS=$'\t' read -r src target; do
            [ -n "$src" ] || continue
            state="$(entry_state "$src" "$target")"
            case "$state" in
                linked)
                    rm "$target"
                    info "unlinked $target"
                    ;;
                missing) ;;
                *)
                    rc=1
                    warn "conflict: refusing to unlink $target"
                    ;;
            esac
        done <<< "$entries"
    done
    return "$rc"
}

cmd_link() {
    local modules=("$@")
    local created=()
    local module src target state entries

    for module in "${modules[@]}"; do
        entries="$(collect_module_entries "$module")" || return 1
        while IFS=$'\t' read -r src target; do
            [ -n "$src" ] || continue
            state="$(entry_state "$src" "$target")"
            case "$state" in
                linked) ;;
                missing)
                    if ! ensure_parent_dir "$target" || ! ln -s "$src" "$target"; then
                        for created_target in "${created[@]}"; do
                            [ -L "$created_target" ] && rm "$created_target"
                        done
                        return 1
                    fi
                    created+=("$target")
                    info "linked $target -> $src"
                    ;;
                *)
                    warn "conflict: refusing to replace $target"
                    for created_target in "${created[@]}"; do
                        [ -L "$created_target" ] && rm "$created_target"
                    done
                    return 1
                    ;;
            esac
        done <<< "$entries"
    done
}

main() {
    local command="${1:-}"
    local -a modules=()

    case "$command" in
        link|list|status|unlink|verify) shift ;;
        --help|-h|"") usage; exit 0 ;;
        *) warn "unknown command: $command"; usage; exit 2 ;;
    esac

    local modules_output
    modules_output="$(resolve_modules "$@")" || exit $?
    if [ -n "$modules_output" ]; then
        mapfile -t modules < <(printf '%s\n' "$modules_output")
    fi
    [ "${#modules[@]}" -gt 0 ] || { warn "no modules selected"; exit 1; }

    case "$command" in
        link) cmd_link "${modules[@]}" ;;
        list) cmd_list "${modules[@]}" ;;
        status) cmd_status "${modules[@]}" ;;
        unlink) cmd_unlink "${modules[@]}" ;;
        verify) cmd_verify "${modules[@]}" ;;
    esac
}

main "$@"
