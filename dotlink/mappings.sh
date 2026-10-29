#!/usr/bin/env bash
# Literal configuration parser. This file never evaluates configuration data.
MAPPING_MODULES=()
MAPPING_SOURCES=()
MAPPING_TARGETS=()
MAPPING_BASES=()
MAPPING_LINES=()
MAPPING_DECLARED=()

mapping_error() {
    # Optional second argument reports a line other than the current one.
    local line="${2:-$MAPPING_LINE}"
    local message="$MAPPING_FILE:$line: "
    [ -z "$MAPPING_MODULE" ] || message+="$MAPPING_MODULE: "
    warn "$message$1"
    return 1
}

mapping_trim() {
    local value="$1"
    value="${value#"${value%%[!$' \t']*}"}"
    value="${value%"${value##*[!$' \t']}"}"
    printf '%s' "$value"
}

mapping_path_valid() {
    case "$1" in
        ''|/*|*/|*//*|.|..|./*|../*|*/./*|*/../*|*/.|*/..) return 1 ;;
    esac
    return 0
}

mapping_finish_link() {
    [ "$MAPPING_LINK" -eq 1 ] || return 0
    [ "$MAPPING_HAVE_SOURCE" -eq 1 ] && [ "$MAPPING_HAVE_TARGET" -eq 1 ] || {
        mapping_error 'link requires source and target'; return 1;
    }
    # Destinations repeat or nest only among links declared in the same module.
    # This is a configuration error, so it is rejected at parse time for every
    # command instead of surfacing later as a selected-inventory overlap.
    local i other
    for ((i=0; i<${#MAPPING_MODULES[@]}; i++)); do
        [ "${MAPPING_MODULES[$i]}" = "$MAPPING_MODULE" ] || continue
        [ "${MAPPING_BASES[$i]}" != "$MAPPING_BASE" ] && continue
        other="${MAPPING_TARGETS[$i]}"
        [ "$MAPPING_TARGET" != "$other" ] || { mapping_error 'duplicate target' "$MAPPING_TARGET_LINE"; return 1; }
        case "$MAPPING_TARGET/" in "$other/"*) mapping_error 'nested target' "$MAPPING_TARGET_LINE"; return 1 ;; esac
        case "$other/" in "$MAPPING_TARGET/"*) mapping_error 'nested target' "$MAPPING_TARGET_LINE"; return 1 ;; esac
    done
    MAPPING_MODULES+=("$MAPPING_MODULE")
    MAPPING_SOURCES+=("$MAPPING_SOURCE")
    MAPPING_TARGETS+=("$MAPPING_TARGET")
    MAPPING_BASES+=("$MAPPING_BASE")
    MAPPING_LINES+=("$MAPPING_LINK_LINE")
    MAPPING_COUNT=$((MAPPING_COUNT + 1))
    MAPPING_LINK=0
}

mapping_finish_module() {
    mapping_finish_link || return 1
    if [ -n "$MAPPING_MODULE" ] && [ "$MAPPING_COUNT" -eq 0 ]; then
        mapping_error 'module requires at least one link'; return 1
    fi
}

mapping_load() {
    local MAPPING_FILE="$REPO_ROOT/dotlink/modules.conf" MAPPING_LINE=0 MAPPING_MODULE=""
    local MAPPING_LINK=0 MAPPING_COUNT=0 MAPPING_LINK_LINE=0 MAPPING_TARGET_LINE=0
    local MAPPING_HAVE_SOURCE=0 MAPPING_HAVE_TARGET=0 MAPPING_HAVE_BASE=0
    local MAPPING_SOURCE="" MAPPING_TARGET="" MAPPING_BASE="home"
    local line key value byte known
    [ ! -L "$MAPPING_FILE" ] || { mapping_error 'configuration must be a real readable regular file'; return 1; }
    [ -e "$MAPPING_FILE" ] || return 0
    [ -f "$MAPPING_FILE" ] && [ -r "$MAPPING_FILE" ] || { mapping_error 'configuration must be a real readable regular file'; return 1; }
    # Bash read discards NUL; examine bytes before reading lines.
    MAPPING_LINE=1
    while read -r byte; do
        for byte in $byte; do
            case "$byte" in
                0) mapping_error 'NUL byte in configuration'; return 1 ;;
                10) MAPPING_LINE=$((MAPPING_LINE + 1)) ;;
            esac
        done
    done < <(od -An -v -tu1 "$MAPPING_FILE")
    MAPPING_LINE=0
    while IFS= read -r line || [ -n "$line" ]; do
        MAPPING_LINE=$((MAPPING_LINE + 1))
        line="${line%$'\r'}"
        line="$(mapping_trim "$line")"
        case "$line" in ''|\#*) continue ;; esac
        if [[ "$line" =~ ^\[module\ ([A-Za-z0-9_-]+)\]$ ]]; then
            mapping_finish_module || return 1
            MAPPING_MODULE="${BASH_REMATCH[1]}"
            dotlink_is_known_module "$REPO_ROOT" "$MAPPING_MODULE" || { mapping_error 'unknown module'; return 1; }
            for known in "${MAPPING_DECLARED[@]}"; do
                [ "$known" != "$MAPPING_MODULE" ] || { mapping_error 'duplicate module'; return 1; }
            done
            MAPPING_DECLARED+=("$MAPPING_MODULE")
            MAPPING_COUNT=0
        elif [ "$line" = '[link]' ]; then
            [ -n "$MAPPING_MODULE" ] || { mapping_error 'link outside module'; return 1; }
            mapping_finish_link || return 1
            MAPPING_LINK=1; MAPPING_LINK_LINE="$MAPPING_LINE"
            MAPPING_HAVE_SOURCE=0; MAPPING_HAVE_TARGET=0; MAPPING_HAVE_BASE=0
            MAPPING_SOURCE=""; MAPPING_TARGET=""; MAPPING_BASE=home; MAPPING_TARGET_LINE=0
        elif [[ "$line" = *'='* ]]; then
            [ "$MAPPING_LINK" -eq 1 ] || { mapping_error 'property outside link'; return 1; }
            key="$(mapping_trim "${line%%=*}")"
            value="$(mapping_trim "${line#*=}")"
            if LC_ALL=C printf '%s' "$value" | LC_ALL=C grep -q '[[:cntrl:]]'; then
                mapping_error 'control byte in value'; return 1
            fi
            case "$key" in
                source)
                    [ "$MAPPING_HAVE_SOURCE" -eq 0 ] || { mapping_error 'duplicate source'; return 1; }
                    mapping_path_valid "$value" || { mapping_error 'invalid source path'; return 1; }
                    MAPPING_HAVE_SOURCE=1; MAPPING_SOURCE="$value" ;;
                target)
                    [ "$MAPPING_HAVE_TARGET" -eq 0 ] || { mapping_error 'duplicate target'; return 1; }
                    mapping_path_valid "$value" || { mapping_error 'invalid target path'; return 1; }
                    MAPPING_HAVE_TARGET=1; MAPPING_TARGET="$value"; MAPPING_TARGET_LINE="$MAPPING_LINE" ;;
                base)
                    [ "$MAPPING_HAVE_BASE" -eq 0 ] || { mapping_error 'duplicate base'; return 1; }
                    case "$value" in home|xdg_config) ;; *) mapping_error 'invalid base'; return 1 ;; esac
                    MAPPING_HAVE_BASE=1; MAPPING_BASE="$value" ;;
                *) mapping_error 'unknown property'; return 1 ;;
            esac
        else
            mapping_error 'malformed header or property'; return 1
        fi
    done < "$MAPPING_FILE"
    mapping_finish_module
}

mapping_is_explicit() {
    local known
    for known in "${MAPPING_DECLARED[@]}"; do
        [ "$known" != "$1" ] || return 0
    done
    return 1
}

mapping_validate_source() {
    local module="$1" relative="$2" path="$REPO_ROOT/$1" rest="$2" segment
    [ ! -L "$path" ] && [ -d "$path" ] || return 1
    while [ -n "$rest" ]; do
        segment="${rest%%/*}"
        if [ "$rest" = "$segment" ]; then rest=""; else rest="${rest#*/}"; fi
        path="$path/$segment"
        [ ! -L "$path" ] || return 1
        if [ -n "$rest" ]; then [ -d "$path" ] || return 1; fi
    done
    [ -f "$path" ] || [ -d "$path" ]
}

# Link validates sources per entry so one missing source cannot drop later links.
mapping_check_source() {
    local module="$1" source="$2" i
    mapping_validate_source "$module" "${source#"$REPO_ROOT/$module/"}" && return 0
    for ((i=0; i<${#MAPPING_MODULES[@]}; i++)); do
        if [ "${MAPPING_MODULES[$i]}" = "$module" ] && [ "$REPO_ROOT/$module/${MAPPING_SOURCES[$i]}" = "$source" ]; then
            warn "$REPO_ROOT/dotlink/modules.conf:${MAPPING_LINES[$i]}: $module: invalid source"
            return 1
        fi
    done
    return 1
}

mapping_collect() {
    local module="$1" i base message source
    for ((i=0; i<${#MAPPING_MODULES[@]}; i++)); do
        [ "${MAPPING_MODULES[$i]}" = "$module" ] || continue
        source="$REPO_ROOT/$module/${MAPPING_SOURCES[$i]}"
        base="$DOTLINK_HOME"
        message=""
        if [ "${MAPPING_BASES[$i]}" = xdg_config ]; then base="${XDG_CONFIG_HOME:-$DOTLINK_HOME/.config}"; fi
        # Validate before encoding rows. An invalid base is an entry failure,
        # not a reason to discard safe home-based siblings in the same module.
        if [[ "$base" = *$'\n'* ]] || LC_ALL=C printf '%s' "$base" | LC_ALL=C grep -q '[[:cntrl:]]'; then
            message='mapping base contains control bytes'
        else
            case "$base" in /*) ;; *) message="mapping base must be an absolute path: $base" ;; esac
        fi
        if [ -n "$message" ]; then
            printf '%s\t-\tinvalid_base\t%s\n' "$source" "$message"
        else
            printf '%s\t%s\n' "$source" "${base%/}/${MAPPING_TARGETS[$i]}"
        fi
    done
}
