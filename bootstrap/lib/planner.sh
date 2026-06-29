#!/usr/bin/env bash

set -euo pipefail

bootstrap_plan_reset() {
    BOOTSTRAP_PLAN_ONLY=()
    BOOTSTRAP_PLAN_SKIP=()
    BOOTSTRAP_PLAN_FORCE=()
    BOOTSTRAP_PLAN_SELECTED=()
    BOOTSTRAP_PLAN_ORDERED=()
    BOOTSTRAP_PLAN_EXECUTE=()
    BOOTSTRAP_PLAN_COMPLETED=()
    BOOTSTRAP_PLAN_CONTEXT_TARGET_USER=""
    BOOTSTRAP_PLAN_CONTEXT_TARGET_HOME=""
    BOOTSTRAP_PLAN_CONTEXT_EFFECTIVE_USER=""
    BOOTSTRAP_PLAN_CONTEXT_EXECUTION=""
    BOOTSTRAP_PLAN_CONTEXT_FRONTEND=""
}

bootstrap_plan_snapshot_context() {
    BOOTSTRAP_PLAN_CONTEXT_TARGET_USER="${BOOTSTRAP_TARGET_USER:-$(bootstrap_target_user)}"
    BOOTSTRAP_PLAN_CONTEXT_TARGET_HOME="${BOOTSTRAP_TARGET_HOME:-$(bootstrap_target_home)}"
    BOOTSTRAP_PLAN_CONTEXT_EFFECTIVE_USER="$(bootstrap_effective_user)"
    BOOTSTRAP_PLAN_CONTEXT_EXECUTION="$(bootstrap_execution_context)"
    BOOTSTRAP_PLAN_CONTEXT_FRONTEND="${BOOTSTRAP_FRONTEND_MODE:-unknown}"
}

bootstrap_plan_validate_known_actions() {
    local action
    for action in "$@"; do
        action="$(bootstrap_action_normalize "$action")"
        if ! bootstrap_action_known "$action"; then
            printf 'Unknown bootstrap action: %s\n' "$action" >&2
            return 3
        fi
    done
}

bootstrap_plan_expand_closure() {
    local changed=true
    local action dep
    local deps=()

    while [ "$changed" = true ]; do
        changed=false
        for action in "${BOOTSTRAP_ACTION_ORDER[@]}"; do
            if bootstrap_array_contains "$action" "${BOOTSTRAP_PLAN_SELECTED[@]}"; then
                bootstrap_action_deps_array "$action" deps
                for dep in "${deps[@]}"; do
                    if [ -n "$dep" ] && ! bootstrap_array_contains "$dep" "${BOOTSTRAP_PLAN_SELECTED[@]}"; then
                        BOOTSTRAP_PLAN_SELECTED+=("$dep")
                        changed=true
                    fi
                done
            fi
        done
    done
}

bootstrap_plan_apply_skip() {
    local -a filtered=()
    local action

    for action in "${BOOTSTRAP_PLAN_SELECTED[@]}"; do
        action="$(bootstrap_action_normalize "$action")"
        if ! bootstrap_array_contains "$action" "${BOOTSTRAP_PLAN_SKIP[@]}"; then
            filtered+=("$action")
        fi
    done

    BOOTSTRAP_PLAN_SELECTED=("${filtered[@]}")
}

bootstrap_plan_validate_closure() {
    local action dep
    local deps=()

    for action in "${BOOTSTRAP_PLAN_SELECTED[@]}"; do
        bootstrap_action_deps_array "$action" deps
        for dep in "${deps[@]}"; do
            if [ -n "$dep" ] && ! bootstrap_array_contains "$dep" "${BOOTSTRAP_PLAN_SELECTED[@]}"; then
                printf 'Bootstrap plan invalid: %s depends on skipped %s\n' "$action" "$dep" >&2
                return 3
            fi
        done
    done
}

bootstrap_plan_compute() {
    local only_csv="${1:-}"
    local skip_csv="${2:-}"
    local force_csv="${3:-}"
    local catalog_hash expected_hash
    local action
    local -a completed_actions=()
    local -a deps=()

    bootstrap_plan_reset
    bootstrap_plan_snapshot_context
    bootstrap_split_csv_into_array "$only_csv" BOOTSTRAP_PLAN_ONLY
    bootstrap_split_csv_into_array "$skip_csv" BOOTSTRAP_PLAN_SKIP
    bootstrap_split_csv_into_array "$force_csv" BOOTSTRAP_PLAN_FORCE

    local -a normalized_only=()
    local -a normalized_skip=()
    local -a normalized_force=()
    local action
    for action in "${BOOTSTRAP_PLAN_ONLY[@]}"; do normalized_only+=("$(bootstrap_action_normalize "$action")"); done
    for action in "${BOOTSTRAP_PLAN_SKIP[@]}"; do normalized_skip+=("$(bootstrap_action_normalize "$action")"); done
    for action in "${BOOTSTRAP_PLAN_FORCE[@]}"; do normalized_force+=("$(bootstrap_action_normalize "$action")"); done
    BOOTSTRAP_PLAN_ONLY=("${normalized_only[@]}")
    BOOTSTRAP_PLAN_SKIP=("${normalized_skip[@]}")
    BOOTSTRAP_PLAN_FORCE=("${normalized_force[@]}")

    bootstrap_plan_validate_known_actions "${BOOTSTRAP_PLAN_ONLY[@]}" "${BOOTSTRAP_PLAN_SKIP[@]}" "${BOOTSTRAP_PLAN_FORCE[@]}" || return $?

    if [ "${#BOOTSTRAP_PLAN_ONLY[@]}" -eq 0 ]; then
        BOOTSTRAP_PLAN_SELECTED=("${BOOTSTRAP_ACTION_ORDER[@]}")
    else
        for action in "${BOOTSTRAP_ACTION_ORDER[@]}"; do
            if bootstrap_array_contains "$action" "${BOOTSTRAP_PLAN_ONLY[@]}"; then
                BOOTSTRAP_PLAN_SELECTED+=("$action")
            fi
        done
    fi

    bootstrap_plan_expand_closure
    bootstrap_plan_apply_skip
    bootstrap_plan_validate_closure || return $?

    BOOTSTRAP_PLAN_ORDERED=()
    for action in "${BOOTSTRAP_ACTION_ORDER[@]}"; do
        if bootstrap_array_contains "$action" "${BOOTSTRAP_PLAN_SELECTED[@]}"; then
            BOOTSTRAP_PLAN_ORDERED+=("$action")
        fi
    done

    expected_hash="$(bootstrap_catalog_hash)"
    if bootstrap_state_is_current "$expected_hash"; then
        while IFS= read -r action; do
            [ -n "$action" ] && completed_actions+=("$action")
        done < <(bootstrap_state_completed_actions "$expected_hash")
    fi

    BOOTSTRAP_PLAN_COMPLETED=("${completed_actions[@]}")
    BOOTSTRAP_PLAN_EXECUTE=()
    for action in "${BOOTSTRAP_PLAN_ORDERED[@]}"; do
        if bootstrap_array_contains "$action" "${BOOTSTRAP_PLAN_FORCE[@]}"; then
            BOOTSTRAP_PLAN_EXECUTE+=("$action")
            continue
        fi

        if ! bootstrap_array_contains "$action" "${BOOTSTRAP_PLAN_COMPLETED[@]}"; then
            BOOTSTRAP_PLAN_EXECUTE+=("$action")
        fi
    done

    BOOTSTRAP_CATALOG_HASH="$expected_hash"
}

bootstrap_plan_assign_csv_field() {
    local field="$1"
    local value="$2"

    case "$field" in
        only) bootstrap_split_csv_into_array "$value" BOOTSTRAP_PLAN_ONLY ;;
        skip) bootstrap_split_csv_into_array "$value" BOOTSTRAP_PLAN_SKIP ;;
        force) bootstrap_split_csv_into_array "$value" BOOTSTRAP_PLAN_FORCE ;;
        ordered) bootstrap_split_csv_into_array "$value" BOOTSTRAP_PLAN_ORDERED ;;
        execute) bootstrap_split_csv_into_array "$value" BOOTSTRAP_PLAN_EXECUTE ;;
        completed) bootstrap_split_csv_into_array "$value" BOOTSTRAP_PLAN_COMPLETED ;;
    esac

    local -a normalized=()
    local item
    case "$field" in
        only)
            for item in "${BOOTSTRAP_PLAN_ONLY[@]}"; do normalized+=("$(bootstrap_action_normalize "$item")"); done
            BOOTSTRAP_PLAN_ONLY=("${normalized[@]}")
            ;;
        skip)
            for item in "${BOOTSTRAP_PLAN_SKIP[@]}"; do normalized+=("$(bootstrap_action_normalize "$item")"); done
            BOOTSTRAP_PLAN_SKIP=("${normalized[@]}")
            ;;
        force)
            for item in "${BOOTSTRAP_PLAN_FORCE[@]}"; do normalized+=("$(bootstrap_action_normalize "$item")"); done
            BOOTSTRAP_PLAN_FORCE=("${normalized[@]}")
            ;;
        ordered)
            for item in "${BOOTSTRAP_PLAN_ORDERED[@]}"; do normalized+=("$(bootstrap_action_normalize "$item")"); done
            BOOTSTRAP_PLAN_ORDERED=("${normalized[@]}")
            ;;
        execute)
            for item in "${BOOTSTRAP_PLAN_EXECUTE[@]}"; do normalized+=("$(bootstrap_action_normalize "$item")"); done
            BOOTSTRAP_PLAN_EXECUTE=("${normalized[@]}")
            ;;
        completed)
            for item in "${BOOTSTRAP_PLAN_COMPLETED[@]}"; do normalized+=("$(bootstrap_action_normalize "$item")"); done
            BOOTSTRAP_PLAN_COMPLETED=("${normalized[@]}")
            ;;
    esac
}

bootstrap_plan_emit_text() {
    local action deps_text status privilege
    local deps=()
    local completed_flag execute_flag forced_flag

    printf 'Bootstrap plan\n'
    printf '  catalog_hash: %s\n' "$BOOTSTRAP_CATALOG_HASH"
    printf '  target_user: %s\n' "$BOOTSTRAP_PLAN_CONTEXT_TARGET_USER"
    printf '  target_home: %s\n' "$BOOTSTRAP_PLAN_CONTEXT_TARGET_HOME"
    printf '  effective_user: %s\n' "$BOOTSTRAP_PLAN_CONTEXT_EFFECTIVE_USER"
    printf '  execution_context: %s\n' "$BOOTSTRAP_PLAN_CONTEXT_EXECUTION"
    printf '  frontend: %s\n' "$BOOTSTRAP_PLAN_CONTEXT_FRONTEND"
    printf '  selected: %s\n' "$(bootstrap_join_csv "${BOOTSTRAP_PLAN_SELECTED[@]}")"
    printf '  execute: %s\n' "$(bootstrap_join_csv "${BOOTSTRAP_PLAN_EXECUTE[@]}")"

    printf '\nActions\n'
    for action in "${BOOTSTRAP_PLAN_ORDERED[@]}"; do
        bootstrap_action_deps_array "$action" deps
        privilege="$(bootstrap_action_privilege "$action")"
        deps_text="$(bootstrap_join_csv "${deps[@]}")"
        completed_flag="no"
        execute_flag="no"
        forced_flag="no"

        if bootstrap_array_contains "$action" "${BOOTSTRAP_PLAN_COMPLETED[@]}"; then
            completed_flag="yes"
        fi
        if bootstrap_array_contains "$action" "${BOOTSTRAP_PLAN_EXECUTE[@]}"; then
            execute_flag="yes"
        fi
        if bootstrap_array_contains "$action" "${BOOTSTRAP_PLAN_FORCE[@]}"; then
            forced_flag="yes"
        fi

        status="pending"
        if [ "$completed_flag" = yes ] && [ "$execute_flag" = no ]; then
            status="satisfied"
        elif [ "$execute_flag" = yes ]; then
            status="execute"
        fi

        printf '  - %s | group=%s | privilege=%s | deps=%s | status=%s | force=%s\n' \
            "$action" \
            "${BOOTSTRAP_ACTION_GROUPS[$action]}" \
            "$privilege" \
            "${deps_text:-none}" \
            "$status" \
            "$forced_flag"
    done
}

bootstrap_plan_emit_json() {
    local action deps_json deps status privilege
    local completed_flag execute_flag forced_flag
    local first=true

    cat <<EOF
{
  "schema_version": ${BOOTSTRAP_SCHEMA_VERSION},
  "catalog_version": ${BOOTSTRAP_CATALOG_VERSION},
  "catalog_hash": $(bootstrap_json_quote "$BOOTSTRAP_CATALOG_HASH"),
  "context": {
    "target_user": $(bootstrap_json_quote "$BOOTSTRAP_PLAN_CONTEXT_TARGET_USER"),
    "target_home": $(bootstrap_json_quote "$BOOTSTRAP_PLAN_CONTEXT_TARGET_HOME"),
    "effective_user": $(bootstrap_json_quote "$BOOTSTRAP_PLAN_CONTEXT_EFFECTIVE_USER"),
    "execution_context": $(bootstrap_json_quote "$BOOTSTRAP_PLAN_CONTEXT_EXECUTION"),
    "frontend": $(bootstrap_json_quote "$BOOTSTRAP_PLAN_CONTEXT_FRONTEND")
  },
  "selection": {
    "only": $(bootstrap_join_json_array "${BOOTSTRAP_PLAN_ONLY[@]}"),
    "skip": $(bootstrap_join_json_array "${BOOTSTRAP_PLAN_SKIP[@]}"),
    "force": $(bootstrap_join_json_array "${BOOTSTRAP_PLAN_FORCE[@]}")
  },
  "ordered": $(bootstrap_join_json_array "${BOOTSTRAP_PLAN_ORDERED[@]}"),
  "execute": $(bootstrap_join_json_array "${BOOTSTRAP_PLAN_EXECUTE[@]}"),
  "completed": $(bootstrap_join_json_array "${BOOTSTRAP_PLAN_COMPLETED[@]}"),
  "actions": [
EOF

    for action in "${BOOTSTRAP_PLAN_ORDERED[@]}"; do
        bootstrap_action_deps_array "$action" deps
        privilege="$(bootstrap_action_privilege "$action")"
        completed_flag=false
        execute_flag=false
        forced_flag=false

        if bootstrap_array_contains "$action" "${BOOTSTRAP_PLAN_COMPLETED[@]}"; then
            completed_flag=true
        fi
        if bootstrap_array_contains "$action" "${BOOTSTRAP_PLAN_EXECUTE[@]}"; then
            execute_flag=true
        fi
        if bootstrap_array_contains "$action" "${BOOTSTRAP_PLAN_FORCE[@]}"; then
            forced_flag=true
        fi

        status="pending"
        if [ "$completed_flag" = true ] && [ "$execute_flag" = false ]; then
            status="satisfied"
        elif [ "$execute_flag" = true ]; then
            status="execute"
        fi

        deps_json="$(bootstrap_join_json_array "${deps[@]}")"

        if [ "$first" = true ]; then
            first=false
        else
            printf ',\n'
        fi
        printf '    {"id": %s, "label": %s, "group": %s, "privilege": %s, "deps": %s, "status": %s, "completed": %s, "execute": %s, "force": %s}' \
            "$(bootstrap_json_quote "$action")" \
            "$(bootstrap_json_quote "${BOOTSTRAP_ACTION_LABELS[$action]}")" \
            "$(bootstrap_json_quote "${BOOTSTRAP_ACTION_GROUPS[$action]}")" \
            "$(bootstrap_json_quote "$privilege")" \
            "$deps_json" \
            "$(bootstrap_json_quote "$status")" \
            "$completed_flag" \
            "$execute_flag" \
            "$forced_flag"
    done

    printf '\n  ]\n}\n'
}

bootstrap_plan_from_json_file() {
    local plan_file="$1"
    local parsed

    bootstrap_plan_reset

    parsed="$(python3 - "$plan_file" <<'PY'
import json, sys

plan = json.load(open(sys.argv[1], 'r', encoding='utf-8'))

context = plan.get('context', {})
for key in ('target_user', 'target_home', 'effective_user', 'execution_context', 'frontend'):
    print(f"context_{key}=" + str(context.get(key, '')))
selection = plan.get('selection', {})
for key in ('only', 'skip', 'force'):
    values = selection.get(key, plan.get(key, []))
    print(f"{key}=" + ",".join(values))
for key in ('ordered', 'execute', 'completed'):
    values = plan.get(key, [])
    print(f"{key}=" + ",".join(values))
print(f"catalog_hash=" + str(plan.get('catalog_hash', '')))
PY
)"

    while IFS='=' read -r key value; do
        case "$key" in
            context_target_user) BOOTSTRAP_PLAN_CONTEXT_TARGET_USER="$value" ;;
            context_target_home) BOOTSTRAP_PLAN_CONTEXT_TARGET_HOME="$value" ;;
            context_effective_user) BOOTSTRAP_PLAN_CONTEXT_EFFECTIVE_USER="$value" ;;
            context_execution_context) BOOTSTRAP_PLAN_CONTEXT_EXECUTION="$value" ;;
            context_frontend) BOOTSTRAP_PLAN_CONTEXT_FRONTEND="$value" ;;
            catalog_hash) BOOTSTRAP_PLAN_CATALOG_HASH="$value" ;;
            only|skip|force|ordered|execute|completed) bootstrap_plan_assign_csv_field "$key" "$value" ;;
        esac
    done <<EOF
$parsed
EOF
}

bootstrap_plan_enforce_context() {
    local recorded_target_user="${BOOTSTRAP_PLAN_CONTEXT_TARGET_USER:-}"
    local recorded_target_home="${BOOTSTRAP_PLAN_CONTEXT_TARGET_HOME:-}"
    local recorded_effective_user="${BOOTSTRAP_PLAN_CONTEXT_EFFECTIVE_USER:-}"
    local recorded_execution_context="${BOOTSTRAP_PLAN_CONTEXT_EXECUTION:-}"
    local current_effective_user current_execution_context

    if [ -z "$recorded_target_user" ] || [ -z "$recorded_target_home" ] || [ -z "$recorded_effective_user" ] || [ -z "$recorded_execution_context" ]; then
        printf 'Saved plan is missing recorded execution context\n' >&2
        return 4
    fi

    current_effective_user="$(bootstrap_effective_user)"
    current_execution_context="$(bootstrap_execution_context)"

    if [ "$recorded_effective_user" != "$current_effective_user" ] || [ "$recorded_execution_context" != "$current_execution_context" ]; then
        printf 'Saved plan context does not match the current shell context\n' >&2
        return 4
    fi

    BOOTSTRAP_TARGET_USER="$recorded_target_user"
    BOOTSTRAP_TARGET_HOME="$recorded_target_home"
}

bootstrap_list_emit_text() {
    local expected_hash
    local action deps_text status privilege
    local deps=()
    local completed=()

    expected_hash="$(bootstrap_catalog_hash)"
    if bootstrap_state_is_current "$expected_hash"; then
        while IFS= read -r action; do
            [ -n "$action" ] && completed+=("$action")
        done < <(bootstrap_state_completed_actions "$expected_hash")
    fi

    printf 'Bootstrap catalog\n'
    printf '  catalog_hash: %s\n' "$expected_hash"
    printf '  target_user: %s\n' "${BOOTSTRAP_TARGET_USER:-$(bootstrap_target_user)}"
    printf '  target_home: %s\n' "${BOOTSTRAP_TARGET_HOME:-$(bootstrap_target_home)}"
    printf '  effective_user: %s\n' "$(bootstrap_effective_user)"
    printf '  execution_context: %s\n' "$(bootstrap_execution_context)"
    printf '\nActions\n'

    for action in "${BOOTSTRAP_ACTION_ORDER[@]}"; do
        bootstrap_action_deps_array "$action" deps
        privilege="$(bootstrap_action_privilege "$action")"
        deps_text="$(bootstrap_join_csv "${deps[@]}")"
        status="pending"
        if bootstrap_array_contains "$action" "${completed[@]}"; then
            status="done"
        fi
        printf '  - %s | group=%s | privilege=%s | deps=%s | status=%s\n' \
            "$action" \
            "${BOOTSTRAP_ACTION_GROUPS[$action]}" \
            "$privilege" \
            "${deps_text:-none}" \
            "$status"
    done
}

bootstrap_list_emit_json() {
    local expected_hash
    local action deps_json status privilege
    local deps=()
    local completed=()
    local first=true

    expected_hash="$(bootstrap_catalog_hash)"
    if bootstrap_state_is_current "$expected_hash"; then
        while IFS= read -r action; do
            [ -n "$action" ] && completed+=("$action")
        done < <(bootstrap_state_completed_actions "$expected_hash")
    fi

    printf '{\n'
    printf '  "schema_version": %s,\n' "${BOOTSTRAP_SCHEMA_VERSION}"
    printf '  "catalog_version": %s,\n' "${BOOTSTRAP_CATALOG_VERSION}"
    printf '  "catalog_hash": %s,\n' "$(bootstrap_json_quote "$expected_hash")"
    printf '  "context": {"target_user": %s, "target_home": %s, "effective_user": %s, "execution_context": %s, "frontend": %s},\n' \
        "$(bootstrap_json_quote "${BOOTSTRAP_TARGET_USER:-$(bootstrap_target_user)}")" \
        "$(bootstrap_json_quote "${BOOTSTRAP_TARGET_HOME:-$(bootstrap_target_home)}")" \
        "$(bootstrap_json_quote "$(bootstrap_effective_user)")" \
        "$(bootstrap_json_quote "$(bootstrap_execution_context)")" \
        "$(bootstrap_json_quote "${BOOTSTRAP_FRONTEND_MODE:-list}")"
    printf '  "actions": [\n'

    for action in "${BOOTSTRAP_ACTION_ORDER[@]}"; do
        bootstrap_action_deps_array "$action" deps
        privilege="$(bootstrap_action_privilege "$action")"
        deps_json="$(bootstrap_join_json_array "${deps[@]}")"
        status="pending"
        if bootstrap_array_contains "$action" "${completed[@]}"; then
            status="done"
        fi

        if [ "$first" = true ]; then
            first=false
        else
            printf ',\n'
        fi
        printf '    {"id": %s, "label": %s, "group": %s, "privilege": %s, "deps": %s, "status": %s}' \
            "$(bootstrap_json_quote "$action")" \
            "$(bootstrap_json_quote "${BOOTSTRAP_ACTION_LABELS[$action]}")" \
            "$(bootstrap_json_quote "${BOOTSTRAP_ACTION_GROUPS[$action]}")" \
            "$(bootstrap_json_quote "$privilege")" \
            "$deps_json" \
            "$(bootstrap_json_quote "$status")"
    done

    printf '\n  ]\n}\n'
}
