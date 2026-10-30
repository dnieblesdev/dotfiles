#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="${DOTLINK_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
DOTLINK_HOME="${DOTLINK_HOME:-$HOME}"

# shellcheck source=manifest.sh
source "$REPO_ROOT/dotlink/manifest.sh"
# shellcheck source=mappings.sh
source "$REPO_ROOT/dotlink/mappings.sh"

usage() {
    cat <<'USAGE'
Usage:
  bin/dotlink link [--report=json] [--profile NAME]
  bin/dotlink list [--profile NAME]
  bin/dotlink status [--profile NAME]
  bin/dotlink unlink [--profile NAME]
  bin/dotlink verify [--profile NAME]

  bin/dotlink link MODULE...
  bin/dotlink status MODULE...
  bin/dotlink unlink MODULE...
  bin/dotlink verify MODULE...

--profile and explicit MODULE arguments are mutually exclusive.
status and verify without arguments scan ALL known modules, not just
the base profile.
Fish links only individual conf.d/*.fish files under absolute XDG_CONFIG_HOME,
or DOTLINK_HOME/.config (HOME by default) when XDG_CONFIG_HOME is empty or unset.
Fish is not selected by existing profiles; absent Fish links fail global verify.
The agents module maps agents/skills to ~/.agents/skills; select it explicitly.
Explicit mappings are declared as literal data in dotlink/modules.conf.
link attempts all safe entries, retains successes, and exits 1 if any entry fails.
It ends with summary: created=N unchanged=N failed=N (stderr in JSON mode).
Only incomplete changes of a failed entry are cleaned up, never earlier successes.
unlink removes repository-owned symlinks even if the source no longer exists,
including ones no selected module describes (reported as drift orphan).
status and verify fail for a selected known module that resolves to no entry.

Dotlink manages repository-owned symlinks only. It never installs packages,
runtimes, tools, or OS provisioning dependencies.
USAGE
}

REPORT_MODE=""
REPORT_FAILURE_MODULE=""
REPORT_FAILURE_SOURCE=""
REPORT_FAILURE_TARGET=""
REPORT_FAILURE_CODE=""
REPORT_FAILURE_MESSAGE=""
REPORT_HAS_FAILURE=0
REPORT_ROLLBACK_ATTEMPTED=0
REPORT_ROLLBACK_COMPLETED=0
REPORT_ENTRY_MODULES=()
REPORT_ENTRY_SOURCES=()
REPORT_ENTRY_TARGETS=()
REPORT_ENTRY_OUTCOMES=()
REPORT_ENTRY_CAUSE_CODES=()
REPORT_ENTRY_CAUSE_MESSAGES=()
REPORT_REMOVED_TARGETS=()
REPORT_REMOVED_DIRECTORIES=()
ENSURED_CREATED_DIRS=()

info() {
    if [ "$REPORT_MODE" = "json" ]; then
        printf 'dotlink: %s\n' "$1" >&2
    else
        printf 'dotlink: %s\n' "$1"
    fi
}
warn() { printf 'dotlink: %s\n' "$1" >&2; }

report_reset() {
    REPORT_FAILURE_MODULE=""
    REPORT_FAILURE_SOURCE=""
    REPORT_FAILURE_TARGET=""
    REPORT_FAILURE_CODE=""
    REPORT_FAILURE_MESSAGE=""
    REPORT_HAS_FAILURE=0
    REPORT_ROLLBACK_ATTEMPTED=0
    REPORT_ROLLBACK_COMPLETED=0
    REPORT_ENTRY_MODULES=()
    REPORT_ENTRY_SOURCES=()
    REPORT_ENTRY_TARGETS=()
    REPORT_ENTRY_OUTCOMES=()
    REPORT_ENTRY_CAUSE_CODES=()
    REPORT_ENTRY_CAUSE_MESSAGES=()
    REPORT_REMOVED_TARGETS=()
    REPORT_REMOVED_DIRECTORIES=()
}

report_add_entry() {
    REPORT_ENTRY_MODULES+=("$1")
    REPORT_ENTRY_SOURCES+=("$2")
    REPORT_ENTRY_TARGETS+=("$3")
    REPORT_ENTRY_OUTCOMES+=("$4")
    REPORT_ENTRY_CAUSE_CODES+=("${5:-}")
    REPORT_ENTRY_CAUSE_MESSAGES+=("${6:-}")
}

report_set_failure() {
    [ "$REPORT_HAS_FAILURE" -eq 0 ] || return 0
    REPORT_HAS_FAILURE=1
    REPORT_FAILURE_MODULE="$1"
    REPORT_FAILURE_SOURCE="$2"
    REPORT_FAILURE_TARGET="$3"
    REPORT_FAILURE_CODE="$4"
    REPORT_FAILURE_MESSAGE="$5"
}

json_string() {
    local value="$1" char escaped="" char_code i
    for ((i = 0; i < ${#value}; i++)); do
        char="${value:i:1}"
        case "$char" in
            '"') escaped+='\"' ;;
            '\') escaped+='\\' ;;
            $'\b') escaped+='\b' ;;
            $'\f') escaped+='\f' ;;
            $'\n') escaped+='\n' ;;
            $'\r') escaped+='\r' ;;
            $'\t') escaped+='\t' ;;
            *)
                printf -v char_code '%d' "'$char"
                if [ "$char_code" -lt 32 ]; then
                    printf -v char '\\u%04x' "$char_code"
                fi
                escaped+="$char"
                ;;
        esac
    done
    printf '"%s"' "$escaped"
}

json_nullable_string() {
    if [ -n "$1" ]; then
        json_string "$1"
    else
        printf 'null'
    fi
}

report_render() {
    local -a modules=("$@")
    local i

    printf '{"schema_version":1,"modules":['
    for ((i = 0; i < ${#modules[@]}; i++)); do
        [ "$i" -eq 0 ] || printf ','
        json_string "${modules[$i]}"
    done
    printf '],"status":'
    if [ "$REPORT_HAS_FAILURE" -eq 1 ]; then printf '"failed"'; else printf '"success"'; fi
    printf ',"entries":['
    for ((i = 0; i < ${#REPORT_ENTRY_MODULES[@]}; i++)); do
        [ "$i" -eq 0 ] || printf ','
        printf '{"module":'; json_string "${REPORT_ENTRY_MODULES[$i]}"
        printf ',"source":'; json_string "${REPORT_ENTRY_SOURCES[$i]}"
        printf ',"target":'; json_string "${REPORT_ENTRY_TARGETS[$i]}"
        printf ',"outcome":'; json_string "${REPORT_ENTRY_OUTCOMES[$i]}"
        if [ -n "${REPORT_ENTRY_CAUSE_CODES[$i]}" ]; then
            printf ',"cause":{"code":'; json_string "${REPORT_ENTRY_CAUSE_CODES[$i]}"
            printf ',"message":'; json_string "${REPORT_ENTRY_CAUSE_MESSAGES[$i]}"
            printf '}'
        fi
        printf '}'
    done
    printf '],"failure":'
    if [ "$REPORT_HAS_FAILURE" -eq 1 ]; then
        printf '{"module":'; json_nullable_string "$REPORT_FAILURE_MODULE"
        printf ',"source":'; json_nullable_string "$REPORT_FAILURE_SOURCE"
        printf ',"target":'; json_nullable_string "$REPORT_FAILURE_TARGET"
        printf ',"cause":{"code":'; json_string "$REPORT_FAILURE_CODE"
        printf ',"message":'; json_string "$REPORT_FAILURE_MESSAGE"
        printf '}}'
    else
        printf 'null'
    fi
    printf ',"rollback":{"attempted":'
    if [ "$REPORT_ROLLBACK_ATTEMPTED" -eq 1 ]; then printf 'true'; else printf 'false'; fi
    printf ',"completed":'
    if [ "$REPORT_ROLLBACK_COMPLETED" -eq 1 ]; then printf 'true'; else printf 'false'; fi
    printf ',"removed_targets":['
    for ((i = 0; i < ${#REPORT_REMOVED_TARGETS[@]}; i++)); do
        [ "$i" -eq 0 ] || printf ','
        json_string "${REPORT_REMOVED_TARGETS[$i]}"
    done
    printf '],"removed_directories":['
    for ((i = 0; i < ${#REPORT_REMOVED_DIRECTORIES[@]}; i++)); do
        [ "$i" -eq 0 ] || printf ','
        json_string "${REPORT_REMOVED_DIRECTORIES[$i]}"
    done
    printf ']}}\n'
}

real_path() {
    local path="$1"
    local result

    # Expand ~ to $HOME up front, before any path resolution.
    case "$path" in
        '~'/*) path="$HOME/${path#\~/}" ;;
        '~') path="$HOME" ;;
    esac

    if command -v realpath >/dev/null 2>&1; then
        if result="$(realpath -m "$path" 2>/dev/null)"; then
            printf '%s\n' "$result"
            return
        fi
    fi

    if command -v python3 >/dev/null 2>&1; then
        if result="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$path" 2>/dev/null)"; then
            printf '%s\n' "$result"
            return
        fi
    fi

    if command -v readlink >/dev/null 2>&1; then
        if result="$(readlink -f "$path" 2>/dev/null)"; then
            printf '%s\n' "$result"
            return
        fi
    fi

    # Pure-shell fallback: normalize . and .. segments for any path.
    __real_path_manual "$path"
}

__real_path_manual() {
    local path="$1"
    local -a stack=()
    local segment is_absolute=0 saved_ifs

    case "$path" in
        /*) is_absolute=1 ;;
    esac

    while [ -n "$path" ]; do
        segment="${path%%/*}"
        path="${path#"$segment"}"
        path="${path#/}"
        case "$segment" in
            ""|.) ;;
            ..)
                if [ "${#stack[@]}" -gt 0 ]; then
                    unset 'stack[-1]'
                elif [ "$is_absolute" -eq 0 ]; then
                    stack+=("..")
                fi
                ;;
            *)
                stack+=("$segment")
                ;;
        esac
    done

    saved_ifs="$IFS"
    IFS='/'
    if [ "$is_absolute" -eq 1 ]; then
        printf '/%s\n' "${stack[*]}"
    elif [ "${#stack[@]}" -gt 0 ]; then
        printf '%s\n' "${stack[*]}"
    else
        printf '.\n'
    fi
    IFS="$saved_ifs"
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
    local file dir inner rel_path target_dir base_error

    [ -d "$src_dir" ] || {
        warn "unknown module: $module"
        return 1
    }
    if mapping_is_explicit "$module"; then
        mapping_collect "$module"
        return $?
    fi

    # Fish shares its configuration directory with the user and vendor tooling.
    # Keep this selection separate: existing modules retain directory-level links.
    if [ "$module" = fish ]; then
        target_dir="${XDG_CONFIG_HOME:-$DOTLINK_HOME/.config}"
        base_error=""
        if [[ "$target_dir" = *$'\n'* ]] || LC_ALL=C printf '%s' "$target_dir" | LC_ALL=C grep -q '[[:cntrl:]]'; then
            base_error="XDG_CONFIG_HOME contains control bytes"
        else
            case "$target_dir" in
                /*) ;;
                *) base_error="XDG_CONFIG_HOME must be an absolute path" ;;
            esac
        fi
        if [ -n "$base_error" ]; then
            printf '%s\t-\tinvalid_base\t%s\n' "$src_dir/.config/fish/conf.d" "$base_error"
            return 0
        fi
        while IFS= read -r -d '' file; do
            printf '%s\t%s\n' "$file" "$target_dir/fish/conf.d/$(basename "$file")"
        done < <(find "$src_dir/.config/fish/conf.d" -maxdepth 1 -type f -name '*.fish' -print0 2>/dev/null | sort -z)
        return 0
    fi

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

collect_orphaned_entries() {
    local target link_target resolved_target

    [ -d "$DOTLINK_HOME" ] || return 0

    while IFS= read -r -d '' target; do
        link_target="$(readlink "$target")"
        case "$link_target" in
            /*) resolved_target="$link_target" ;;
            *)  resolved_target="$(dirname "$target")/$link_target" ;;
        esac

        # Report every repository-owned symlink here. Broken links are always
        # orphaned; a functional one is orphaned only when no selected module
        # accounts for its destination, which the caller filters by target.
        is_repo_path "$resolved_target" || continue

        printf '%s\t%s\n' "$resolved_target" "$target"
    done < <(find "$DOTLINK_HOME" -type l -print0 2>/dev/null)
}

resolve_modules() {
    local profile="base"
    local profile_set=0
    local -a explicit=()
    local module

    while [ $# -gt 0 ]; do
        case "$1" in
            --profile)
                [ $# -ge 2 ] || { warn "--profile requires a name"; return 2; }
                profile="$2"
                profile_set=1
                shift 2
                ;;
            --profile=*)
                profile="${1#--profile=}"
                profile_set=1
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

    if [ "$profile_set" -eq 1 ] && [ "${#explicit[@]}" -gt 0 ]; then
        warn "cannot combine --profile with explicit modules"
        return 2
    fi

    if [ "${#explicit[@]}" -gt 0 ]; then
        for module in "${explicit[@]}"; do
            if ! dotlink_is_known_module "$REPO_ROOT" "$module"; then
                warn "unknown module: $module"
                if [ "$REPORT_MODE" = "json" ]; then
                    report_set_failure "$module" "" "" "unknown_module" "unknown module: $module"
                fi
                return 1
            fi
        done
        printf '%s\n' "${explicit[@]}"
        return 0
    fi

    dotlink_load_profile "$REPO_ROOT" "$profile" || return 1
    printf '%s\n' "${DOTLINK_PROFILE_MODULES[@]}"
}

validate_fish_parent_dir() {
    local target="$1"
    local path component rest
    path="$(dirname "$target")"

    rest="${path#/}"
    component=""
    while [ -n "$rest" ]; do
        local segment="${rest%%/*}"
        if [ "$rest" = "$segment" ]; then rest=""; else rest="${rest#*/}"; fi
        case "$segment" in
            "") continue ;;
            .|..)
                warn "Fish destination may not contain . or .. components"
                return 1
                ;;
        esac
        component="$component/$segment"
        if [ -L "$component" ]; then
            warn "conflict: parent is not a real directory: $component"
            return 1
        fi
        if [ -e "$component" ] && [ ! -d "$component" ]; then
            warn "conflict: parent is not a real directory: $component"
            return 1
        fi
    done
}

ensure_parent_dir() {
    local target="$1"
    local parent candidate i
    local -a missing=()
    parent="$(dirname "$target")"
    ENSURED_CREATED_DIRS=()

    candidate="$parent"
    while [ ! -d "$candidate" ]; do
        if [ -e "$candidate" ] || [ -L "$candidate" ]; then
            warn "conflict: parent is not a real directory: $candidate"
            return 1
        fi
        missing+=("$candidate")
        candidate="$(dirname "$candidate")"
    done
    [ ! -L "$candidate" ] || { warn "conflict: parent is not a real directory: $candidate"; return 1; }

    for ((i = ${#missing[@]} - 1; i >= 0; i--)); do
        mkdir "$candidate/${missing[$i]##*/}" 2>/dev/null || mkdir "${missing[$i]}" || return 1
        candidate="${missing[$i]}"
        ENSURED_CREATED_DIRS+=("$candidate")
    done
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

# Validate selected inventory before any lifecycle operation can write.
validate_inventory() {
    shift # Command is reserved for lifecycle-specific validation.
    local module entries src target cause message prior resolved
    local -a targets=()
    local -A visited=()
    for module in "$@"; do
        # Repeating a selection is not a duplicate mapping declaration.
        [ -z "${visited[$module]:-}" ] || continue
        visited["$module"]=1
        entries="$(collect_module_entries "$module")" || return 1
        while IFS=$'\t' read -r src target cause message; do
            [ -n "$src" ] || continue
            [ -z "$cause" ] || continue # No destination exists for this failed resolution.
            # Compare destination locations, not the referents of existing links.
            # Distinct links may legitimately point to the same source.
            resolved="$(real_path "$(dirname "$target")")"
            resolved="${resolved%/}/$(basename "$target")"
            for prior in "${targets[@]}"; do
                case "$resolved/" in "$prior/"|"$prior/"*)
                    warn "overlapping targets: $prior and $resolved"; return 1 ;;
                esac
                case "$prior/" in "$resolved/"*)
                    warn "overlapping targets: $prior and $resolved"; return 1 ;;
                esac
            done
            targets+=("$resolved")
        done <<< "$entries"
    done
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
    local module src target cause message state entries rc=0 declared=0
    local -A seen_targets=() reported_modules=()

    for module in "${modules[@]}"; do
        declared=0
        entries="$(collect_module_entries "$module")" || return 1
        while IFS=$'\t' read -r src target cause message; do
            [ -n "$src" ] || continue
            if [ -n "$cause" ]; then warn "$message"; return 1; fi
            if mapping_is_explicit "$module" && ! mapping_check_source "$module" "$src"; then return 1; fi
            seen_targets["$target"]=1
            if mapping_is_explicit "$module" && ! validate_fish_parent_dir "$target" 2>/dev/null; then
                state=conflict
            else
                state="$(entry_state "$src" "$target")"
            fi
            # An optional module that is not present on this platform is skipped,
            # not reported as missing, so the all-module scan stays platform-safe.
            if [ "$state" = missing ] && dotlink_is_optional_module "$module"; then
                state=skip
            fi
            [ "$state" != conflict ] || rc=1
            declared=1
            printf '%s\t%s\t%s\n' "$state" "$module" "$target"
        done <<< "$entries"
        reported_modules["$module"]=$declared
    done

    # Every known module's declared targets, so an unselected sibling's link is
    # never mistaken for an orphan of this selection.
    local -A declared_targets=()
    local other
    while IFS= read -r other; do
        [ -n "$other" ] || continue
        while IFS=$'\t' read -r src target cause message; do
            [ -n "$target" ] || continue
            [ -n "$cause" ] && continue
            declared_targets["$target"]=1
        done <<< "$(collect_module_entries "$other")"
    done < <(dotlink_list_known_modules "$REPO_ROOT")

    # Surface repo-owned symlinks no selected module accounts for: broken ones
    # always, functional ones only when their destination is unclaimed.
    local -A orphan_modules=()
    while IFS=$'\t' read -r src target cause message; do
        [ -n "$target" ] || continue
        [ -z "${seen_targets[$target]:-}" ] || continue
        [ -z "${declared_targets[$target]:-}" ] || continue
        state="$(entry_state "$src" "$target")"
        [ "$state" != conflict ] || rc=1
        # Attribute the orphan to its module in its own map: an orphan is not an
        # entry, so it must never overwrite what the module actually declared.
        case "$src" in
            "$REPO_ROOT"/*)
                module="${src#"$REPO_ROOT"/}"
                orphan_modules["${module%%/*}"]=1
                ;;
        esac
        # An unclaimed link is stale by definition, however its referent resolves.
        [ "$state" = conflict ] || state=drift
        printf '%s\t%s\t%s\n' "$state" "orphan" "$target"
    done < <(collect_orphaned_entries)

    # A known module that resolves to no entry at all cannot be reported as
    # healthy. A module whose only output is orphan drift already surfaced its
    # own problem and keeps its historical exit status.
    for module in "${modules[@]}"; do
        [ "${reported_modules[$module]:-0}" -eq 0 ] || continue
        dotlink_is_optional_module "$module" && continue
        warn "$REPO_ROOT/$module: no entries discovered; declare explicit mappings or add dot entries"
        rc=1
    done
    return "$rc"
}

cmd_verify() {
    local modules=("$@")
    local module src target cause message state entries rc=0 declared=0
    local -A seen_targets=()

    for module in "${modules[@]}"; do
        declared=0
        entries="$(collect_module_entries "$module")" || return 1
        while IFS=$'\t' read -r src target cause message; do
            [ -n "$src" ] || continue
            if [ -n "$cause" ]; then warn "$message"; return 1; fi
            if mapping_is_explicit "$module" && ! mapping_check_source "$module" "$src"; then return 1; fi
            seen_targets["$target"]=1
            declared=1
            if mapping_is_explicit "$module" && ! validate_fish_parent_dir "$target" 2>/dev/null; then
                state=conflict
            else
                state="$(entry_state "$src" "$target")"
            fi
            if [ "$state" != linked ]; then
                # An absent optional module is a platform skip, not a failure.
                # verify stays silent on success: reporting skip here would make
                # an exit-0 verify emit output that callers read as a problem.
                if [ "$state" = missing ] && dotlink_is_optional_module "$module"; then
                    :
                else
                    rc=1
                    printf '%s\t%s\t%s\n' "$state" "$module" "$target"
                fi
            fi
        done <<< "$entries"
        # Verification of a module with nothing to check is not a pass. An absent
        # optional module is a platform skip, so it keeps the historical exemption.
        if [ "$declared" -eq 0 ] && ! dotlink_is_optional_module "$module"; then
            warn "$REPO_ROOT/$module: no entries discovered; declare explicit mappings or add dot entries"
            rc=1
        fi
    done

    # Unclaimed repo-owned symlinks fail verification; a sibling module's link is
    # claimed and therefore not an orphan of this selection.
    local -A declared_targets=()
    local other
    while IFS= read -r other; do
        [ -n "$other" ] || continue
        while IFS=$'\t' read -r src target cause message; do
            [ -n "$target" ] || continue
            [ -n "$cause" ] && continue
            declared_targets["$target"]=1
        done <<< "$(collect_module_entries "$other")"
    done < <(dotlink_list_known_modules "$REPO_ROOT")

    while IFS=$'\t' read -r src target cause message; do
        [ -n "$target" ] || continue
        [ -z "${seen_targets[$target]:-}" ] || continue
        [ -z "${declared_targets[$target]:-}" ] || continue
        state="$(entry_state "$src" "$target")"
        if [ "$state" != linked ]; then
            rc=1
            printf '%s\t%s\t%s\n' "$state" "orphan" "$target"
        fi
    done < <(collect_orphaned_entries)

    return "$rc"
}

cmd_unlink() {
    local modules=("$@")
    local module src target cause message state entries rc=0
    local -A seen_targets=()

    for module in "${modules[@]}"; do
        entries="$(collect_module_entries "$module")" || return 1
        while IFS=$'\t' read -r src target cause message; do
            [ -n "$src" ] || continue
            if [ -n "$cause" ]; then warn "$message"; return 1; fi
            # Ownership, not source existence, authorizes removal: a moved or
            # deleted source must never strand a symlink this repository owns.
            seen_targets["$target"]=1
            if mapping_is_explicit "$module" && ! validate_fish_parent_dir "$target" 2>/dev/null; then
                state=conflict
            else
                state="$(entry_state "$src" "$target")"
            fi
            case "$state" in
                linked|drift)
                    # drift still means this repository owns the symlink; only the
                    # referent moved. Removal stays authorized.
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

    # Remove repo-owned symlinks that no selected module describes. Every other
    # module's declared targets must be treated as claimed, or unlinking one
    # module would delete its siblings' links.
    local -A declared_targets=()
    local other
    while IFS= read -r other; do
        [ -n "$other" ] || continue
        while IFS=$'\t' read -r src target cause message; do
            [ -n "$target" ] || continue
            [ -n "$cause" ] && continue
            declared_targets["$target"]=1
        done <<< "$(collect_module_entries "$other")"
    done < <(dotlink_list_known_modules "$REPO_ROOT")

    while IFS=$'\t' read -r src target cause message; do
        [ -n "$target" ] || continue
        [ -z "${seen_targets[$target]:-}" ] || continue
        [ -z "${declared_targets[$target]:-}" ] || continue
        state="$(entry_state "$src" "$target")"
        case "$state" in
            linked|drift)
                rm "$target"
                info "unlinked orphaned $target"
                ;;
            missing) ;;
            *)
                rc=1
                warn "conflict: refusing to unlink $target"
                ;;
        esac
    done < <(collect_orphaned_entries)

    return "$rc"
}

rollback_link() {
    local target dir i complete=1
    local -a sorted_dirs=()

    if [ "$REPORT_ROLLBACK_ATTEMPTED" -eq 0 ]; then REPORT_ROLLBACK_COMPLETED=1; fi
    REPORT_ROLLBACK_ATTEMPTED=1
    for target in "${created[@]}"; do
        if [ -L "$target" ] && rm "$target"; then
            REPORT_REMOVED_TARGETS+=("$target")
            report_mark_rolled_back "$target"
        else
            complete=0
            warn "rollback: unable to remove $target"
        fi
    done

    # Remove created parent directories if empty. Sort so parents precede
    # children, then iterate in reverse to remove children first.
    if [ "${#created_dirs[@]}" -gt 0 ]; then
        mapfile -t sorted_dirs < <(printf '%s\n' "${created_dirs[@]}" | sort -u)
    fi
    for (( i=${#sorted_dirs[@]}-1; i>=0; i-- )); do
        dir="${sorted_dirs[$i]}"
        if rmdir "$dir" 2>/dev/null; then
            REPORT_REMOVED_DIRECTORIES+=("$dir")
        else
            complete=0
            warn "rollback: unable to remove $dir"
        fi
    done
    # A later successful cleanup must not hide an earlier cleanup failure.
    if [ "$complete" -eq 0 ]; then REPORT_ROLLBACK_COMPLETED=0; fi
}

report_mark_rolled_back() {
    local target="$1" i
    for ((i = 0; i < ${#REPORT_ENTRY_TARGETS[@]}; i++)); do
        if [ "${REPORT_ENTRY_TARGETS[$i]}" = "$target" ] && [ "${REPORT_ENTRY_OUTCOMES[$i]}" = "changed" ]; then
            REPORT_ENTRY_OUTCOMES[$i]="rolled_back"
            return 0
        fi
    done
}

cmd_link() {
    local modules=("$@")
    local created=()
    local created_dirs=()
    local module src target cause message state entries failure_message
    local count_created=0 count_unchanged=0 count_failed=0
    local -A visited=()

    for module in "${modules[@]}"; do
        [ -z "${visited[$module]:-}" ] || continue
        visited["$module"]=1
        if ! entries="$(collect_module_entries "$module")"; then
            report_set_failure "$module" "" "" "inventory_error" "unable to collect module: $module"
            count_failed=$((count_failed + 1))
            continue
        fi
        while IFS=$'\t' read -r src target cause message; do
            [ -n "$src" ] || continue
            created=(); created_dirs=()
            if [ -n "$cause" ]; then
                warn "$message"
                report_add_entry "$module" "$src" "" "failed" "$cause" "$message"
                report_set_failure "$module" "$src" "" "$cause" "$message"
                count_failed=$((count_failed + 1))
                continue
            fi
            if mapping_is_explicit "$module" && ! mapping_check_source "$module" "$src"; then
                failure_message="invalid mapping source: $src"
                report_add_entry "$module" "$src" "$target" "failed" "invalid_source" "$failure_message"
                report_set_failure "$module" "$src" "$target" "invalid_source" "$failure_message"
                count_failed=$((count_failed + 1))
                continue
            fi
            if { [ "$module" = fish ] || mapping_is_explicit "$module"; } && ! validate_fish_parent_dir "$target"; then
                failure_message="unable to create parent directory for $target"
                report_add_entry "$module" "$src" "$target" "failed" "parent_conflict" "$failure_message"
                report_set_failure "$module" "$src" "$target" "parent_conflict" "$failure_message"
                count_failed=$((count_failed + 1))
                continue
            fi
            state="$(entry_state "$src" "$target")"
            case "$state" in
                linked)
                    report_add_entry "$module" "$src" "$target" "unchanged"
                    count_unchanged=$((count_unchanged + 1))
                    ;;
                missing)
                    if ! ensure_parent_dir "$target"; then
                        created_dirs+=("${ENSURED_CREATED_DIRS[@]}")
                        failure_message="unable to create parent directory for $target"
                        report_add_entry "$module" "$src" "$target" "failed" "parent_conflict" "$failure_message"
                        report_set_failure "$module" "$src" "$target" "parent_conflict" "$failure_message"
                        rollback_link
                        count_failed=$((count_failed + 1))
                        continue
                    fi
                    created_dirs+=("${ENSURED_CREATED_DIRS[@]}")
                    if ! ln -s "$src" "$target"; then
                        failure_message="unable to link $target to $src"
                        warn "$failure_message"
                        report_add_entry "$module" "$src" "$target" "failed" "link_error" "$failure_message"
                        report_set_failure "$module" "$src" "$target" "link_error" "$failure_message"
                        rollback_link
                        count_failed=$((count_failed + 1))
                        continue
                    fi
                    created+=("$target")
                    count_created=$((count_created + 1))
                    report_add_entry "$module" "$src" "$target" "changed"
                    info "linked $target -> $src"
                    ;;
                *)
                    failure_message="conflict: refusing to replace $target"
                    warn "$failure_message"
                    report_add_entry "$module" "$src" "$target" "failed" "conflict" "$failure_message"
                    report_set_failure "$module" "$src" "$target" "conflict" "$failure_message"
                    count_failed=$((count_failed + 1))
                    ;;
            esac
        done <<< "$entries"
    done
    info "summary: created=$count_created unchanged=$count_unchanged failed=$count_failed"
    [ "$count_failed" -eq 0 ]
}

main() {
    local command="${1:-}" rc arg profile_requested=0
    local -a modules=() link_args=()

    case "$command" in
        link|list|status|unlink|verify) shift ;;
        --help|-h|"") usage; exit 0 ;;
        *) warn "unknown command: $command"; usage; exit 2 ;;
    esac

    if [ "$command" = "link" ]; then
        for arg in "$@"; do
            case "$arg" in
                --profile|--profile=*)
                    profile_requested=1
                    link_args+=("$arg")
                    ;;
                --report=json)
                    REPORT_MODE="json"
                    report_reset
                    ;;
                --report=*)
                    warn "unsupported report value: ${arg#--report=}"
                    exit 2
                    ;;
                *) link_args+=("$arg") ;;
            esac
        done
        set -- "${link_args[@]}"
    fi

    # status/verify without args: scan ALL known modules, not just base profile.
    if { [ "$command" = "status" ] || [ "$command" = "verify" ]; } && [ $# -eq 0 ]; then
        local all_known
        all_known="$(dotlink_list_known_modules "$REPO_ROOT")"
        [ -n "$all_known" ] || { warn "no known modules found"; exit 1; }
        mapfile -t modules < <(printf '%s\n' "$all_known")
    else
        local modules_output
        if modules_output="$(resolve_modules "$@")"; then
            :
        else
            rc=$?
            if [ "$REPORT_MODE" = "json" ]; then
                if [ "$profile_requested" -eq 0 ]; then
                    for arg in "$@"; do
                        case "$arg" in
                            --*) ;;
                            *)
                                if ! dotlink_is_known_module "$REPO_ROOT" "$arg"; then
                                    report_set_failure "$arg" "" "" "unknown_module" "unknown module: $arg"
                                    break
                                fi
                                ;;
                        esac
                    done
                fi
                [ "$REPORT_HAS_FAILURE" -eq 1 ] || report_set_failure "" "" "" "selection_error" "module selection failed"
                report_render
            fi
            exit "$rc"
        fi
        if [ -n "$modules_output" ]; then
            mapfile -t modules < <(printf '%s\n' "$modules_output")
        fi
    fi
    if [ "${#modules[@]}" -eq 0 ]; then
        warn "no modules selected"
        if [ "$REPORT_MODE" = "json" ]; then
            report_set_failure "" "" "" "selection_error" "no modules selected"
            report_render
        fi
        exit 1
    fi

    if ! mapping_load; then
        if [ "$REPORT_MODE" = json ]; then
            report_set_failure "" "" "" "mapping_error" "invalid mapping configuration"
            report_render "${modules[@]}"
        fi
        return 1
    fi
    if [ "$command" != list ] && ! validate_inventory "$command" "${modules[@]}"; then
        if [ "$REPORT_MODE" = json ]; then
            report_set_failure "" "" "" "inventory_error" "invalid mapping inventory"
            report_render "${modules[@]}"
        fi
        return 1
    fi

    case "$command" in
        link)
            if cmd_link "${modules[@]}"; then rc=0; else rc=$?; fi
            if [ "$REPORT_MODE" = "json" ]; then report_render "${modules[@]}"; fi
            return "$rc"
            ;;
        list) cmd_list "${modules[@]}" ;;
        status) cmd_status "${modules[@]}" ;;
        unlink) cmd_unlink "${modules[@]}" ;;
        verify) cmd_verify "${modules[@]}" ;;
    esac
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
