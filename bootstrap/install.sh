#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/lib/util.sh"
source "$SCRIPT_DIR/lib/catalog.sh"
source "$SCRIPT_DIR/lib/controller.sh"
source "$SCRIPT_DIR/lib/state.sh"
source "$SCRIPT_DIR/lib/planner.sh"

DOTFILES_REPO="https://github.com/dnieblesdev/dotfiles.git"
DOTFILES_DIR="$HOME/.dotfiles"
BACKUP_DIR="$HOME/.dotfiles-backup-$(date +%Y%m%d-%H%M%S)"
BOOTSTRAP_BREW_BIN=""

APT_PACKAGES=(git curl wget openssh-client build-essential unzip tar file procps python3)
PACMAN_PACKAGES=(git curl wget openssh base-devel unzip tar file procps-ng python3)
BREW_TOOL_SPECS=(
    "eza|eza"
    "bat|bat"
    "fd|fd"
    "ripgrep|ripgrep"
    "fzf|fzf"
    "zoxide|zoxide"
    "starship|starship"
    "neovim|neovim"
    "lazygit|lazygit"
    "bottom|bottom"
    "dua|dua-cli"
    "tldr|tealdeer"
)

# ── Utils ──
info() { printf '  \033[36m→\033[0m %s\n' "$1"; }
ok() { printf '  \033[32m✓\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m⚠\033[0m %s\n' "$1"; }
err() { printf '  \033[31m✗\033[0m %s\n' "$1"; }

run_privileged() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
        return $?
    fi

    if ! command_exists sudo; then
        printf 'sudo-unavailable\n' >&2
        return 127
    fi

    if [ -z "${BOOTSTRAP_PRIVILEGED_DISPATCH_CONFIRMED:-}" ]; then
        if ! bootstrap_confirm_privileged_dispatch; then
            return $?
        fi
    fi

    sudo /usr/bin/env PATH="$(bootstrap_trusted_child_path)" "$@"
}

detect_package_manager() {
    if command_exists apt; then
        printf '%s\n' apt
    elif command_exists pacman; then
        printf '%s\n' pacman
    fi
}

is_wsl() {
    local version=""
    if [ -r /proc/version ]; then
        version="$(</proc/version)"
    fi

    case "$version" in
        *microsoft*|*Microsoft*) return 0 ;;
    esac

    return 1
}

is_linux() {
    [ "$(uname)" = Linux ] && ! is_wsl
}

bootstrap_brew_candidate_paths() {
    local target_home

    target_home="$(bootstrap_target_home)"

    type -aP brew 2>/dev/null || true
    printf '%s\n' \
        "$target_home/.linuxbrew/bin/brew" \
        "$target_home/.homebrew/bin/brew" \
        "/home/linuxbrew/.linuxbrew/bin/brew" \
        "/opt/homebrew/bin/brew" \
        "/usr/local/bin/brew"

    printf '%s\n' \
        "/Applications/Homebrew.app/Contents/Resources/homebrew/bin/brew" \
        "/Applications/Homebrew.app/Contents/Resources/usr/local/bin/brew" \
        "/Applications/Homebrew.app/Contents/Resources/bin/brew"
}

bootstrap_brew_binary_matches_target_owner() {
    local brew_bin="$1"
    local target_user
    local target_uid=""
    local resolved_brew_bin=""
    local prefix_root=""
    local path_owner=""
    local prefix_owner=""

    if [ -z "$brew_bin" ]; then
        return 1
    fi

    target_user="$(bootstrap_target_user)"
    target_uid="$(id -u "$target_user" 2>/dev/null || true)"
    if [ -z "$target_uid" ]; then
        return 1
    fi

    resolved_brew_bin="$(bootstrap_path_realpath "$brew_bin" 2>/dev/null || true)"
    if [ -z "$resolved_brew_bin" ] || [ ! -x "$resolved_brew_bin" ]; then
        return 1
    fi

    prefix_root="$(dirname "$(dirname "$resolved_brew_bin")")"
    path_owner="$(bootstrap_path_owner_uid "$resolved_brew_bin" 2>/dev/null || true)"
    prefix_owner="$(bootstrap_path_owner_uid "$prefix_root" 2>/dev/null || true)"

    [ "$path_owner" = "$target_uid" ] && [ "$prefix_owner" = "$target_uid" ]
}

find_brew_binary() {
    local candidate
    local candidate_owner
    local prefix_owner
    local prefix_root
    local resolved_candidate
    local target_user
    local target_uid=""

    target_user="$(bootstrap_target_user)"
    target_uid="$(id -u "$target_user" 2>/dev/null || true)"

    while IFS= read -r candidate; do
        [ -n "$candidate" ] || continue
        [ -x "$candidate" ] || continue

        resolved_candidate="$(bootstrap_path_realpath "$candidate" 2>/dev/null || true)"
        [ -n "$resolved_candidate" ] || continue
        [ -x "$resolved_candidate" ] || continue

        prefix_root="$(dirname "$(dirname "$resolved_candidate")")"
        candidate_owner="$(bootstrap_path_owner_uid "$resolved_candidate" 2>/dev/null || true)"
        prefix_owner="$(bootstrap_path_owner_uid "$prefix_root" 2>/dev/null || true)"

        if [ -n "$target_uid" ] && [ "$candidate_owner" = "$target_uid" ] && [ "$prefix_owner" = "$target_uid" ]; then
            printf '%s\n' "$resolved_candidate"
            return 0
        fi

        if [ -n "$target_uid" ] && [ -n "$candidate_owner" ] && [ -n "$prefix_owner" ]; then
            warn "Ignoring brew at $candidate -> $resolved_candidate because ownership uid $candidate_owner and prefix uid $prefix_owner do not match target uid $target_uid"
        fi
    done <<EOF
$(bootstrap_brew_candidate_paths)
EOF

    return 1
}

install_system_packages() {
    local manager="$1"

    case "$manager" in
        apt)
            info "Updating apt metadata"
            if ! run_privileged apt update -qq; then
                warn "apt metadata update failed"
            fi
            info "Installing system packages with apt"
            if run_privileged apt install -y -qq "${APT_PACKAGES[@]}"; then
                ok "System packages installed"
            else
                warn "Some apt packages could not be installed. Continuing with what is already available."
            fi
            ;;
        pacman)
            info "Installing system packages with pacman"
            if run_privileged pacman -Syu --noconfirm --needed "${PACMAN_PACKAGES[@]}"; then
                ok "System packages installed"
            else
                warn "Some pacman packages could not be installed. Continuing with what is already available."
            fi
            ;;
        *)
            warn "No supported system package manager detected. Install git, curl, wget, openssh, build tools, unzip, and tar manually."
            ;;
    esac
}

bootstrap_homebrew_setup() {
    local brew_bin

    brew_bin="$(find_brew_binary || true)"
    if [ -n "$brew_bin" ]; then
        info "Homebrew found at $brew_bin"
    else
        info "Homebrew not found; installing it now"
        if ! command_exists curl; then
            warn "curl is required to bootstrap Homebrew. Skipping Homebrew and brew-managed tools."
            return 1
        fi

        if ! NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
            warn "Homebrew installation failed. Skipping brew-managed tools."
            return 1
        fi

        brew_bin="$(find_brew_binary || true)"
        if [ -z "$brew_bin" ]; then
            warn "Homebrew installed but the brew binary could not be located. Skipping brew-managed tools."
            return 1
        fi
    fi

    if ! "$brew_bin" --version >/dev/null 2>&1; then
        warn "Homebrew verification failed. Skipping brew-managed tools."
        return 1
    fi

    BOOTSTRAP_BREW_BIN="$brew_bin"
    ok "Homebrew ready"
}

install_brew_formula() {
    local label="$1"
    local formula="${2:-$1}"
    local brew_bin="${BOOTSTRAP_BREW_BIN:-}"

    if [ -z "$brew_bin" ]; then
        warn "Skipping $label: Homebrew is unavailable"
        return 0
    fi

    if "$brew_bin" list "$formula" >/dev/null 2>&1; then
        info "$label already installed"
        return 0
    fi

    info "Installing $label with Homebrew"
    if "$brew_bin" install "$formula" >/dev/null 2>&1; then
        if "$brew_bin" list "$formula" >/dev/null 2>&1; then
            ok "$label installed"
        else
            warn "Homebrew finished but $label could not be verified"
        fi
    else
        warn "Could not install $label with Homebrew. Continuing without it."
    fi
}

install_brew_dev_tools() {
    if [ -z "${BOOTSTRAP_BREW_BIN:-}" ]; then
        warn "Homebrew is unavailable; skipping brew-managed developer tools"
        return 0
    fi

    local spec label formula
    for spec in "${BREW_TOOL_SPECS[@]}"; do
        IFS='|' read -r label formula <<<"$spec"
        install_brew_formula "$label" "$formula"
    done
}

clone_or_update_dotfiles() {
    if [ -d "$DOTFILES_DIR" ]; then
        info "$DOTFILES_DIR already exists; updating it"
        if git -C "$DOTFILES_DIR" pull --ff-only >/dev/null 2>&1; then
            ok "Dotfiles updated"
        else
            warn "Could not update the dotfiles repository (local changes?)"
        fi
    else
        git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
        ok "Dotfiles cloned into $DOTFILES_DIR"
    fi
}

backup_existing_shell_files() {
    local needs_backup=false
    local file

    for file in .bashrc .zshrc .profile .gitconfig; do
        if [ -f "$HOME/$file" ] && [ ! -L "$HOME/$file" ]; then
            needs_backup=true
            break
        fi
    done

    if [ "$needs_backup" = true ]; then
        mkdir -p "$BACKUP_DIR"
        for file in .bashrc .zshrc .profile .gitconfig; do
            if [ -f "$HOME/$file" ] && [ ! -L "$HOME/$file" ]; then
                cp "$HOME/$file" "$BACKUP_DIR/$file"
                info "Backed up $HOME/$file -> $BACKUP_DIR/$file"
            fi
        done
        ok "Backup created in $BACKUP_DIR"
    else
        info "No original shell files found to back up"
    fi
}

link_dotfiles() {
    chmod +x "$DOTFILES_DIR/bootstrap/dotlink"
    "$DOTFILES_DIR/bootstrap/dotlink" bash git zsh config

    if is_wsl; then
        "$DOTFILES_DIR/bootstrap/dotlink" wsl
    elif is_linux; then
        "$DOTFILES_DIR/bootstrap/dotlink" linux
    fi

    ok "Dotfiles linked"
}

install_nvm_runtime() {
    if [ -d "$HOME/.nvm" ]; then
        info "nvm already installed"
        return 0
    fi

    info "Installing nvm"
    if curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash; then
        ok "nvm installed"
    else
        warn "Could not install nvm. Continuing."
    fi
}

install_uv_runtime() {
    if command_exists uv; then
        info "uv already installed"
        return 0
    fi

    info "Installing uv"
    if curl -fsSL https://astral.sh/uv/install.sh | sh; then
        ok "uv installed"
    else
        warn "Could not install uv. Continuing."
    fi
}

install_rustup_runtime() {
    if command_exists rustc && command_exists cargo; then
        info "Rust already installed"
        return 0
    fi

    info "Installing Rust"
    if curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y 2>/dev/null; then
        ok "Rust installed"
    else
        warn "Could not install Rust. Continuing."
    fi
}

bootstrap_run_action() {
    local action="$1"

    case "$action" in
        system-packages)
            install_system_packages "$(detect_package_manager || true)"
            ;;
        homebrew-bootstrap)
            bootstrap_homebrew_setup
            ;;
        brew-tools)
            install_brew_dev_tools
            ;;
        dotfiles-clone)
            clone_or_update_dotfiles
            ;;
        dotfiles-backup)
            backup_existing_shell_files
            ;;
        dotfiles-link)
            link_dotfiles
            ;;
        runtime-nvm)
            install_nvm_runtime
            ;;
        runtime-uv)
            install_uv_runtime
            ;;
        runtime-rustup)
            install_rustup_runtime
            ;;
        *)
            err "Unknown action: $action"
            return 3
            ;;
    esac
}

bootstrap_spawn_shell_action() {
    local user_mode="$1"
    local action="$2"
    local target_user
    local target_home
    local script_path="$SCRIPT_DIR/install.sh"

    target_user="$(bootstrap_target_user)"
    target_home="$(bootstrap_target_home)"

    if [ "$user_mode" = "root" ]; then
        if [ "$(bootstrap_effective_uid)" -eq 0 ]; then
            source "$SCRIPT_DIR/lib/util.sh"
            source "$SCRIPT_DIR/lib/catalog.sh"
            source "$SCRIPT_DIR/lib/state.sh"
            source "$SCRIPT_DIR/lib/planner.sh"
            if bootstrap_run_action "$action"; then
                return 0
            else
                return $?
            fi
        fi
        run_privileged bash -c 'source "$1"; source "$(dirname "$1")/lib/util.sh"; source "$(dirname "$1")/lib/catalog.sh"; source "$(dirname "$1")/lib/state.sh"; source "$(dirname "$1")/lib/planner.sh"; bootstrap_run_action "$2"' _ "$script_path" "$action"
        return $?
    fi

    if [ "$user_mode" = "user" ] && [ "$(bootstrap_effective_uid)" -eq 0 ] && [ -n "$target_user" ] && [ "$target_user" != root ]; then
        if ! command_exists sudo; then
            err "Cannot demote $action to $target_user because sudo is unavailable"
            return 4
        fi

        target_home="${target_home:-$(bootstrap_home_for_user "$target_user")}"
        local -a scrubbed_sudo_env=()

        bootstrap_sudo_env_scrub_args scrubbed_sudo_env

        sudo -u "$target_user" /usr/bin/env "${scrubbed_sudo_env[@]}" \
            HOME="$target_home" \
            USER="$target_user" \
            LOGNAME="$target_user" \
            PATH="$(bootstrap_trusted_child_path)" \
            SHELL="${SHELL:-/bin/bash}" \
            TERM="${TERM:-xterm-256color}" \
            BASH_ENV= \
            /bin/bash -c 'source "$1"; source "$(dirname "$1")/lib/util.sh"; source "$(dirname "$1")/lib/catalog.sh"; source "$(dirname "$1")/lib/state.sh"; source "$(dirname "$1")/lib/planner.sh"; bootstrap_run_action "$2"' _ "$script_path" "$action"
        return $?
    fi

    if [ "$user_mode" = "user" ] && bootstrap_user_action_requires_root_refusal "$action" "$target_user"; then
        err "Refusing to run $action as root. Re-run as the intended user or set BOOTSTRAP_ROOT_OWNED_ACTIONS to opt into root-owned ownership for this action."
        return 4
    fi

    source "$SCRIPT_DIR/lib/util.sh"
    source "$SCRIPT_DIR/lib/catalog.sh"
    source "$SCRIPT_DIR/lib/state.sh"
    source "$SCRIPT_DIR/lib/planner.sh"
    bootstrap_run_action "$action"
}

bootstrap_execute_action() {
    local action="$1"
    local privilege
    if privilege="$(bootstrap_action_privilege "$action")"; then
        :
    else
        return $?
    fi

    case "$privilege" in
        user)
            bootstrap_spawn_shell_action user "$action"
            ;;
        elevated)
            bootstrap_spawn_shell_action root "$action"
            ;;
        mixed)
            bootstrap_spawn_shell_action user "$action"
            ;;
        *)
            err "Unknown privilege model for action: $action"
            return 3
            ;;
    esac
}

bootstrap_show_startup_context() {
    local command_name="${1:-apply}"
    BOOTSTRAP_FRONTEND_MODE="$command_name"
    BOOTSTRAP_TARGET_USER="$(bootstrap_target_user)"
    BOOTSTRAP_TARGET_HOME="$(bootstrap_target_home)"
    BOOTSTRAP_EFFECTIVE_USER="$(bootstrap_effective_user)"
    BOOTSTRAP_EFFECTIVE_UID="$(bootstrap_effective_uid)"
    BOOTSTRAP_EXECUTION_CONTEXT="$(bootstrap_execution_context)"

    printf '  target user: %s\n' "$BOOTSTRAP_TARGET_USER"
    printf '  target home: %s\n' "$BOOTSTRAP_TARGET_HOME"
    printf '  effective user: %s\n' "$BOOTSTRAP_EFFECTIVE_USER"
    printf '  execution context: %s\n' "$BOOTSTRAP_EXECUTION_CONTEXT"
    printf '  frontend mode: %s\n' "$BOOTSTRAP_FRONTEND_MODE"
}

bootstrap_confirm_root_warning() {
    if [ -n "${BOOTSTRAP_ROOT_WARNING_CONFIRMED:-}" ]; then
        return 0
    fi

    if [ "$(bootstrap_effective_uid)" -ne 0 ]; then
        return 0
    fi

    if bootstrap_test_mode_enabled && [ -n "${BOOTSTRAP_AUTO_CONFIRM:-}" ]; then
        case "${BOOTSTRAP_AUTO_CONFIRM}" in
            1|yes|YES|true|TRUE|y|Y)
                BOOTSTRAP_ROOT_WARNING_CONFIRMED=1
                return 0
                ;;
        esac
    fi

    warn "Running bootstrap/install.sh as root is risky."
    warn "Re-run as a non-root user to keep brew-managed tools user-owned by default."
    warn "Continuing as root will install system packages and may modify system files."

    local confirm_rc=0
    bootstrap_prompt_yes_no "Continue running bootstrap as root?" 30
    confirm_rc=$?

    case "$confirm_rc" in
        0)
            BOOTSTRAP_ROOT_WARNING_CONFIRMED=1
            return 0
            ;;
        1)
            printf 'root-warning-denied\n' >&2
            return 4
            ;;
        *)
            printf 'root-warning-timeout\n' >&2
            return 5
            ;;
    esac
}

bootstrap_confirm_privileged_dispatch() {
    local confirm_rc=0

    if [ -n "${BOOTSTRAP_PRIVILEGED_DISPATCH_CONFIRMED:-}" ]; then
        return 0
    fi

    if [ "$(bootstrap_effective_uid)" -eq 0 ]; then
        BOOTSTRAP_PRIVILEGED_DISPATCH_CONFIRMED=1
        return 0
    fi

    bootstrap_prompt_yes_no "Continue with sudo-mediated privileged execution?" 30
    confirm_rc=$?
    if [ "$confirm_rc" -eq 0 ]; then
        BOOTSTRAP_PRIVILEGED_DISPATCH_CONFIRMED=1
        return 0
    fi

    case "$confirm_rc" in
        1)
            printf 'confirmation-denied\n' >&2
            return 4
            ;;
        2)
            printf 'confirmation-timeout\n' >&2
            return 5
            ;;
        *)
            printf 'confirmation-timeout\n' >&2
            return 5
            ;;
    esac
}

bootstrap_parse_args() {
    BOOTSTRAP_COMMAND="apply"
    BOOTSTRAP_FORMAT="text"
    BOOTSTRAP_PLAN_FILE=""
    local -a only=()
    local -a skip=()
    local -a force=()
    local -a positional=()

    case "${1:-}" in
        plan|apply|list|controller|test|help|-h|--help)
            BOOTSTRAP_COMMAND="$1"
            shift || true
            ;;
    esac

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --only)
                only+=("${2:-}")
                shift 2
                ;;
            --only=*)
                only+=("${1#--only=}")
                shift
                ;;
            --skip)
                skip+=("${2:-}")
                shift 2
                ;;
            --skip=*)
                skip+=("${1#--skip=}")
                shift
                ;;
            --force)
                force+=("${2:-}")
                shift 2
                ;;
            --force=*)
                force+=("${1#--force=}")
                shift
                ;;
            --format)
                BOOTSTRAP_FORMAT="${2:-text}"
                shift 2
                ;;
            --format=*)
                BOOTSTRAP_FORMAT="${1#--format=}"
                shift
                ;;
            --plan)
                BOOTSTRAP_PLAN_FILE="${2:-}"
                shift 2
                ;;
            --plan=*)
                BOOTSTRAP_PLAN_FILE="${1#--plan=}"
                shift
                ;;
            --)
                shift
                while [ "$#" -gt 0 ]; do
                    positional+=("$1")
                    shift
                done
                ;;
            -h|--help)
                BOOTSTRAP_COMMAND="help"
                shift
                ;;
            *)
                positional+=("$1")
                shift
                ;;
        esac
    done

    if [ "$BOOTSTRAP_COMMAND" = "apply" ] && [ "${#positional[@]}" -gt 0 ] && [ "${#only[@]}" -eq 0 ]; then
        only+=("${positional[@]}")
    fi

    if [ "$BOOTSTRAP_COMMAND" = "plan" ] && [ "${#positional[@]}" -gt 0 ] && [ "${#only[@]}" -eq 0 ]; then
        only+=("${positional[@]}")
    fi

    BOOTSTRAP_FRONTEND_MODE="$BOOTSTRAP_COMMAND"
    BOOTSTRAP_ONLY_CSV="$(bootstrap_join_csv "${only[@]}")"
    BOOTSTRAP_SKIP_CSV="$(bootstrap_join_csv "${skip[@]}")"
    BOOTSTRAP_FORCE_CSV="$(bootstrap_join_csv "${force[@]}")"
}

bootstrap_execute_plan() {
    local action rc
    local -a completed=("${BOOTSTRAP_PLAN_COMPLETED[@]}")
    local only_csv="${BOOTSTRAP_ONLY_CSV:-$(bootstrap_join_csv "${BOOTSTRAP_PLAN_ONLY[@]}")}"
    local skip_csv="${BOOTSTRAP_SKIP_CSV:-$(bootstrap_join_csv "${BOOTSTRAP_PLAN_SKIP[@]}")}"
    local force_csv="${BOOTSTRAP_FORCE_CSV:-$(bootstrap_join_csv "${BOOTSTRAP_PLAN_FORCE[@]}")}"
    local ordered_csv="$(bootstrap_join_csv "${BOOTSTRAP_PLAN_ORDERED[@]}")"
    local execute_csv="$(bootstrap_join_csv "${BOOTSTRAP_PLAN_EXECUTE[@]}")"

    for action in "${BOOTSTRAP_PLAN_EXECUTE[@]}"; do
        printf '\n\033[1m[%s]\033[0m\n' "$action"
        if bootstrap_execute_action "$action"; then
            if ! bootstrap_array_contains "$action" "${completed[@]}"; then
                completed+=("$action")
            fi
            bootstrap_state_write \
                "$BOOTSTRAP_CATALOG_HASH" \
                "partial_success" \
                "" \
                0 \
                "" \
                "$only_csv" \
                "$skip_csv" \
                "$force_csv" \
                "$ordered_csv" \
                "$execute_csv" \
                "$(bootstrap_join_csv "${completed[@]}")"
            continue
        else
            rc=$?
        fi
        bootstrap_state_write \
            "$BOOTSTRAP_CATALOG_HASH" \
            "partial_failure" \
            "$action" \
            "$rc" \
            "Action failed" \
            "$only_csv" \
            "$skip_csv" \
            "$force_csv" \
            "$ordered_csv" \
            "$execute_csv" \
            "$(bootstrap_join_csv "${completed[@]}")"
        return "$rc"
    done

    bootstrap_state_write \
        "$BOOTSTRAP_CATALOG_HASH" \
        "success" \
        "" \
        0 \
        "" \
        "$only_csv" \
        "$skip_csv" \
        "$force_csv" \
        "$ordered_csv" \
        "$execute_csv" \
        "$(bootstrap_join_csv "${completed[@]}")"
}

bootstrap_command_plan() {
    bootstrap_parse_args "$@"
    BOOTSTRAP_FRONTEND_MODE="plan"

    if [ -n "$BOOTSTRAP_PLAN_FILE" ]; then
        bootstrap_plan_from_json_file "$BOOTSTRAP_PLAN_FILE"
    fi

    bootstrap_plan_compute "$BOOTSTRAP_ONLY_CSV" "$BOOTSTRAP_SKIP_CSV" "$BOOTSTRAP_FORCE_CSV"

    case "$BOOTSTRAP_FORMAT" in
        json) bootstrap_plan_emit_json ;;
        text|*) bootstrap_plan_emit_text ;;
    esac
}

bootstrap_command_apply() {
    bootstrap_parse_args "$@"
    BOOTSTRAP_FRONTEND_MODE="apply"
    bootstrap_confirm_root_warning
    local current_hash=""

    if [ -n "$BOOTSTRAP_PLAN_FILE" ]; then
        bootstrap_plan_from_json_file "$BOOTSTRAP_PLAN_FILE"
        current_hash="$(bootstrap_catalog_hash)"
        if [ -z "${BOOTSTRAP_PLAN_CATALOG_HASH:-}" ]; then
            err "Saved plan is missing a catalog hash"
            return 4
        fi
        if [ "$BOOTSTRAP_PLAN_CATALOG_HASH" != "$current_hash" ]; then
            err "Saved plan catalog hash does not match the current catalog"
            return 4
        fi

        if ! bootstrap_plan_enforce_context; then
            return 4
        fi

        local saved_ordered_csv saved_execute_csv
        saved_ordered_csv="$(bootstrap_join_csv "${BOOTSTRAP_PLAN_ORDERED[@]}")"
        saved_execute_csv="$(bootstrap_join_csv "${BOOTSTRAP_PLAN_EXECUTE[@]}")"
        BOOTSTRAP_CATALOG_HASH="$current_hash"
        BOOTSTRAP_ONLY_CSV="$(bootstrap_join_csv "${BOOTSTRAP_PLAN_ONLY[@]}")"
        BOOTSTRAP_SKIP_CSV="$(bootstrap_join_csv "${BOOTSTRAP_PLAN_SKIP[@]}")"
        BOOTSTRAP_FORCE_CSV="$(bootstrap_join_csv "${BOOTSTRAP_PLAN_FORCE[@]}")"
        bootstrap_plan_compute "$BOOTSTRAP_ONLY_CSV" "$BOOTSTRAP_SKIP_CSV" "$BOOTSTRAP_FORCE_CSV"
        if ! bootstrap_plan_revalidate_saved_replay "$saved_ordered_csv" "$saved_execute_csv"; then
            return 4
        fi
    else
        bootstrap_plan_compute "$BOOTSTRAP_ONLY_CSV" "$BOOTSTRAP_SKIP_CSV" "$BOOTSTRAP_FORCE_CSV"
    fi
    local rc=0
    if bootstrap_execute_plan; then
        :
    else
        rc=$?
        return "$rc"
    fi

    if [ ! -d "$HOME/development/flutter" ]; then
        warn "Flutter not detected. If you need it: https://docs.flutter.dev/get-started/install/linux"
    fi

    echo ""
    printf '\033[1m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n'
    printf '\033[1m  ✅ Bootstrap completed\033[0m\n'
    printf '\033[1m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n\n'
    echo "  Close and reopen your terminal for the changes to take effect."
    echo "  The bootstrap does NOT change your default shell automatically."
    echo "  If you want to switch to Zsh, review the config first: chsh -s \"$(command -v zsh || echo /usr/bin/zsh)\""
    echo "  If something does not work, run: dotlink --list"
    echo
}

bootstrap_command_list() {
    bootstrap_parse_args "$@"
    BOOTSTRAP_FRONTEND_MODE="list"

    case "$BOOTSTRAP_FORMAT" in
        json) bootstrap_list_emit_json ;;
        text|*) bootstrap_list_emit_text ;;
    esac
}

bootstrap_command_controller() {
    bootstrap_controller_handle_request
}

bootstrap_self_test() {
    local temp_dir temp_state temp_state_seed temp_plan temp_stale_plan temp_tampered_plan temp_tampered_state temp_malicious_plan temp_wrong_frontend_state temp_wrong_frontend_plan
    local -a execution_trace=()
    local -a warning_trace=()
    local baseline_hash mutated_hash
    local rc
    temp_dir="$(mktemp -d)"
    temp_state="$temp_dir/bootstrap-state.json"
    temp_state_seed="$temp_dir/bootstrap-state-seed.json"
    temp_plan="$temp_dir/bootstrap-plan.json"
    temp_stale_plan="$temp_dir/bootstrap-plan-stale.json"
    temp_tampered_plan="$temp_dir/bootstrap-plan-tampered.json"
    temp_tampered_state="$temp_dir/bootstrap-state-tampered.json"
    temp_malicious_plan="$temp_dir/bootstrap-plan-malicious.json"
    temp_wrong_frontend_state="$temp_dir/bootstrap-state-wrong-frontend.json"
    temp_wrong_frontend_plan="$temp_dir/bootstrap-plan-wrong-frontend.json"

    local real_uid real_user
    real_uid="$(id -u)"
    real_user="$(id -un)"

    local saved_bootstrap_target_user="${BOOTSTRAP_TARGET_USER:-}"
    local saved_bootstrap_target_home="${BOOTSTRAP_TARGET_HOME:-}"
    local saved_bootstrap_test_mode_active="${BOOTSTRAP_TEST_MODE_ACTIVE:-}"
    local saved_bootstrap_test_mode="${BOOTSTRAP_TEST_MODE:-}"
    BOOTSTRAP_TARGET_USER=""
    BOOTSTRAP_TARGET_HOME=""
    BOOTSTRAP_TEST_MODE_ACTIVE=""
    BOOTSTRAP_TEST_MODE=""

    bootstrap_effective_uid() {
        printf '0\n'
    }

    bootstrap_effective_user() {
        printf 'root\n'
    }

    local saved_bootstrap_sudo_provenance_trusted
    saved_bootstrap_sudo_provenance_trusted="$(declare -f bootstrap_sudo_provenance_trusted)"
    bootstrap_sudo_provenance_trusted() {
        return 1
    }

    if [ "$(SUDO_USER="$real_user" SUDO_UID="$real_uid" bootstrap_target_user)" != "root" ]; then
        err "Expected stale sudo identity to be ignored without provenance evidence"
        return 1
    fi

    if [ "$(SUDO_USER="$real_user" SUDO_UID="$real_uid" bootstrap_execution_context)" != "root-shell" ]; then
        err "Expected stale sudo identity to stay root-shell without provenance evidence"
        return 1
    fi

    bootstrap_sudo_provenance_trusted() {
        return 0
    }

    if [ "$(SUDO_USER="$real_user" SUDO_UID="$real_uid" bootstrap_target_user)" != "$real_user" ]; then
        err "Expected valid sudo provenance to resolve the target user"
        return 1
    fi

    if [ "$(SUDO_USER="$real_user" SUDO_UID="$real_uid" bootstrap_execution_context)" != "root-via-sudo" ]; then
        err "Expected valid sudo provenance to resolve the execution context"
        return 1
    fi

    eval "$saved_bootstrap_sudo_provenance_trusted"

    BOOTSTRAP_TEST_MODE=1
    BOOTSTRAP_TARGET_USER="alice"
    BOOTSTRAP_TARGET_HOME="/home/alice"
    if [ "$(bootstrap_target_user)" != "root" ]; then
        err "Expected target user overrides to be ignored without explicit test mode"
        return 1
    fi
    if [ "$(bootstrap_target_home)" != "/root" ]; then
        err "Expected target home overrides to be ignored without explicit test mode"
        return 1
    fi

    BOOTSTRAP_AUTO_CONFIRM=1

    if bootstrap_prompt_yes_no "Confirm override requires test mode"; then
        err "Expected auto-confirm to be ignored without explicit test mode"
        return 1
    fi

    BOOTSTRAP_TEST_MODE_ACTIVE=1

    if [ "$(bootstrap_target_user)" != "alice" ]; then
        err "Expected target user overrides to work in explicit test mode"
        return 1
    fi
    if [ "$(bootstrap_target_home)" != "/home/alice" ]; then
        err "Expected target home overrides to work in explicit test mode"
        return 1
    fi

    local -a warning_trace=()

    warn() {
        warning_trace+=("warn:$*")
    }

    local saved_bootstrap_effective_uid
    local saved_bootstrap_prompt_yes_no
    local saved_command_exists
    local saved_bootstrap_trusted_child_path_entries
    local saved_bootstrap_path_owner_uid
    local saved_sudo_function=""

    saved_bootstrap_effective_uid="$(declare -f bootstrap_effective_uid)"
    saved_bootstrap_prompt_yes_no="$(declare -f bootstrap_prompt_yes_no)"
    saved_command_exists="$(declare -f command_exists)"
    saved_bootstrap_trusted_child_path_entries="$(declare -f bootstrap_trusted_child_path_entries)"
    saved_bootstrap_path_owner_uid="$(declare -f bootstrap_path_owner_uid)"
    if declare -f sudo >/dev/null 2>&1; then
        saved_sudo_function="$(declare -f sudo)"
    fi

    local -a confirm_trace=()
    local -a sudo_trace=()
    local expected_trusted_path
    local saw_trusted_path=false
    local saw_raw_path=false
    local arg

    bootstrap_effective_uid() {
        printf '1000\n'
    }

    bootstrap_prompt_yes_no() {
        confirm_trace+=("$1:$2")
        return 0
    }

    command_exists() {
        [ "$1" = sudo ] && return 0
        return 1
    }

    sudo() {
        sudo_trace=("$@")
        "$@"
    }

    expected_trusted_path="$(bootstrap_trusted_child_path)"
    if ! run_privileged true >/dev/null 2>&1; then
        err "Expected privileged dispatch to succeed with auto-confirm"
        return 1
    fi
    if ! run_privileged true >/dev/null 2>&1; then
        err "Expected privileged dispatch to stay confirmed within the same phase"
        return 1
    fi

    if [ "${#confirm_trace[@]}" -ne 1 ]; then
        err "Expected privileged confirmation to happen once per sudo phase"
        return 1
    fi

    for arg in "${sudo_trace[@]}"; do
        case "$arg" in
            PATH="$expected_trusted_path") saw_trusted_path=true ;;
            PATH=*) saw_raw_path=true ;;
        esac
    done

    if [ "$saw_trusted_path" != true ] || [ "$saw_raw_path" = true ]; then
        err "Expected privileged child launches to use the trusted PATH only"
        return 1
    fi

    unset BOOTSTRAP_PRIVILEGED_DISPATCH_CONFIRMED
    bootstrap_prompt_yes_no() {
        return 1
    }
    if bootstrap_confirm_privileged_dispatch >/tmp/bootstrap-confirm-denied.out 2>&1; then
        err "Expected confirmation denial to fail closed"
        return 1
    fi
    if ! grep -q 'confirmation-denied' /tmp/bootstrap-confirm-denied.out; then
        err "Expected confirmation denial to report confirmation-denied"
        return 1
    fi

    bootstrap_prompt_yes_no() {
        return 2
    }
    if bootstrap_confirm_privileged_dispatch >/tmp/bootstrap-confirm-timeout.out 2>&1; then
        err "Expected confirmation timeout to fail closed"
        return 1
    fi
    if ! grep -q 'confirmation-timeout' /tmp/bootstrap-confirm-timeout.out; then
        err "Expected confirmation timeout to report confirmation-timeout"
        return 1
    fi

    command_exists() {
        return 1
    }
    if run_privileged true >/tmp/bootstrap-sudo-unavailable.out 2>&1; then
        err "Expected missing sudo to fail closed"
        return 1
    fi
    if ! grep -q 'sudo-unavailable' /tmp/bootstrap-sudo-unavailable.out; then
        err "Expected missing sudo to report sudo-unavailable"
        return 1
    fi

    command_exists() {
        [ "$1" = sudo ] && return 0
        return 1
    }

    local saved_bootstrap_trusted_child_path_entries_missing
    local saved_bootstrap_trusted_child_path_entries_unowned
    local saved_bootstrap_trusted_child_path_entries_writable
    local saved_bootstrap_path_owner_uid_writable
    local missing_trusted_dir unowned_trusted_dir writable_trusted_dir

    missing_trusted_dir="$temp_dir/missing-trusted/bin"
    unowned_trusted_dir="$temp_dir/unowned-trusted/bin"
    writable_trusted_dir="$temp_dir/writable-trusted/bin"
    mkdir -p "$(dirname "$unowned_trusted_dir")" "$(dirname "$writable_trusted_dir")"
    mkdir -p "$unowned_trusted_dir" "$writable_trusted_dir"
    chmod 755 "$unowned_trusted_dir"
    chmod 777 "$writable_trusted_dir"

    bootstrap_trusted_child_path_entries() {
        printf '%s\n' "$missing_trusted_dir"
    }
    if bootstrap_trusted_child_path >/tmp/bootstrap-trusted-path-missing.out 2>&1; then
        err "Expected missing trusted PATH entries to fail closed"
        return 1
    fi
    if ! grep -q 'trusted-path-invalid' /tmp/bootstrap-trusted-path-missing.out; then
        err "Expected missing trusted PATH entries to report trusted-path-invalid"
        return 1
    fi

    bootstrap_trusted_child_path_entries() {
        printf '%s\n' "$unowned_trusted_dir"
    }
    if bootstrap_trusted_child_path >/tmp/bootstrap-trusted-path-unowned.out 2>&1; then
        err "Expected non-root-owned trusted PATH entries to fail closed"
        return 1
    fi
    if ! grep -q 'trusted-path-invalid' /tmp/bootstrap-trusted-path-unowned.out; then
        err "Expected non-root-owned trusted PATH entries to report trusted-path-invalid"
        return 1
    fi

    saved_bootstrap_path_owner_uid_writable="$(declare -f bootstrap_path_owner_uid)"
    bootstrap_path_owner_uid() {
        case "$1" in
            "$writable_trusted_dir")
                printf '0\n'
                ;;
            *)
                printf '0\n'
                ;;
        esac
    }
    bootstrap_trusted_child_path_entries() {
        printf '%s\n' "$writable_trusted_dir"
    }
    if bootstrap_trusted_child_path >/tmp/bootstrap-trusted-path-writable.out 2>&1; then
        err "Expected writable trusted PATH entries to fail closed"
        return 1
    fi
    if ! grep -q 'trusted-path-invalid' /tmp/bootstrap-trusted-path-writable.out; then
        err "Expected writable trusted PATH entries to report trusted-path-invalid"
        return 1
    fi

    local temp_shadow_dir temp_shadow_bash child_bash_path
    temp_shadow_dir="$temp_dir/shadow-path"
    mkdir -p "$temp_shadow_dir"
    temp_shadow_bash="$temp_shadow_dir/bash"
    cat >"$temp_shadow_bash" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "shadow-bash"
EOF
    chmod +x "$temp_shadow_bash"

    bootstrap_path_owner_uid() {
        printf '0\n'
    }
    bootstrap_trusted_child_path_entries() {
        printf '%s\n' /usr/bin /bin /usr/sbin /sbin
    }
    sudo() {
        "$@"
    }
    bootstrap_effective_uid() {
        printf '1000\n'
    }
    bootstrap_prompt_yes_no() {
        return 0
    }

    child_bash_path="$(PATH="$temp_shadow_dir:${PATH:-/usr/bin:/bin}" run_privileged bash -c 'command -v bash')"
    if [ "$child_bash_path" = "$temp_shadow_bash" ]; then
        err "Expected privileged child resolution to ignore caller PATH shadowing"
        return 1
    fi

    eval "$saved_bootstrap_effective_uid"
    eval "$saved_bootstrap_prompt_yes_no"
    eval "$saved_command_exists"
    eval "$saved_bootstrap_trusted_child_path_entries"
    eval "$saved_bootstrap_path_owner_uid"
    if [ -n "$saved_sudo_function" ]; then
        eval "$saved_sudo_function"
    else
        unset -f sudo 2>/dev/null || true
    fi

    local saved_root_warning_effective_uid saved_root_warning_prompt
    saved_root_warning_effective_uid="$(declare -f bootstrap_effective_uid)"
    saved_root_warning_prompt="$(declare -f bootstrap_prompt_yes_no)"

    local saved_root_warning_auto_confirm="${BOOTSTRAP_AUTO_CONFIRM:-}"
    local saved_root_warning_confirmed="${BOOTSTRAP_ROOT_WARNING_CONFIRMED:-}"
    BOOTSTRAP_AUTO_CONFIRM=""
    BOOTSTRAP_ROOT_WARNING_CONFIRMED=""

    bootstrap_effective_uid() { printf '1000\n'; }
    bootstrap_prompt_yes_no() {
        err "Expected non-root to skip the warning prompt"
        return 99
    }
    if ! bootstrap_confirm_root_warning; then
        err "Expected non-root confirm_root_warning to succeed"
        return 1
    fi

    bootstrap_effective_uid() { printf '0\n'; }
    bootstrap_prompt_yes_no() {
        err "Expected auto-confirm to skip the warning prompt"
        return 99
    }
    BOOTSTRAP_AUTO_CONFIRM="1"
    if ! bootstrap_confirm_root_warning; then
        err "Expected auto-confirm to confirm root warning"
        return 1
    fi
    if [ "${BOOTSTRAP_ROOT_WARNING_CONFIRMED:-}" != "1" ]; then
        err "Expected auto-confirm to set the root warning flag"
        return 1
    fi

    BOOTSTRAP_AUTO_CONFIRM=""
    BOOTSTRAP_ROOT_WARNING_CONFIRMED=""
    bootstrap_prompt_yes_no() { return 0; }
    if ! bootstrap_confirm_root_warning; then
        err "Expected user confirm to succeed"
        return 1
    fi
    if [ "${BOOTSTRAP_ROOT_WARNING_CONFIRMED:-}" != "1" ]; then
        err "Expected user confirm to set the root warning flag"
        return 1
    fi

    BOOTSTRAP_ROOT_WARNING_CONFIRMED=""
    bootstrap_prompt_yes_no() { return 1; }
    if bootstrap_confirm_root_warning >/tmp/bootstrap-root-warning-denied.out 2>&1; then
        err "Expected user deny to fail closed"
        return 1
    fi
    if ! grep -q 'root-warning-denied' /tmp/bootstrap-root-warning-denied.out; then
        err "Expected user deny to report root-warning-denied"
        return 1
    fi

    BOOTSTRAP_ROOT_WARNING_CONFIRMED=""
    bootstrap_prompt_yes_no() { return 2; }
    if bootstrap_confirm_root_warning >/tmp/bootstrap-root-warning-timeout.out 2>&1; then
        err "Expected root warning timeout to fail closed"
        return 1
    fi
    if ! grep -q 'root-warning-timeout' /tmp/bootstrap-root-warning-timeout.out; then
        err "Expected root warning timeout to report root-warning-timeout"
        return 1
    fi

    BOOTSTRAP_ROOT_WARNING_CONFIRMED="1"
    bootstrap_prompt_yes_no() {
        err "Expected idempotent call to skip the warning prompt"
        return 99
    }
    if ! bootstrap_confirm_root_warning; then
        err "Expected idempotent confirm to succeed"
        return 1
    fi

    eval "$saved_root_warning_effective_uid"
    eval "$saved_root_warning_prompt"
    BOOTSTRAP_AUTO_CONFIRM="$saved_root_warning_auto_confirm"
    if [ -n "$saved_root_warning_confirmed" ]; then
        BOOTSTRAP_ROOT_WARNING_CONFIRMED="$saved_root_warning_confirmed"
    else
        unset BOOTSTRAP_ROOT_WARNING_CONFIRMED
    fi

    bootstrap_run_action() {
        execution_trace+=("run:$1")
        return 17
    }

    if bootstrap_spawn_shell_action root "homebrew-bootstrap" >/dev/null 2>&1; then
        err "Expected root-shell action failures to propagate"
        return 1
    else
        rc=$?
    fi

    if [ "$rc" -ne 17 ]; then
        err "Expected root-shell action to return the underlying failure"
        return 1
    fi

    bootstrap_run_action() {
        return 23
    }

    bootstrap_effective_uid() {
        printf '0\n'
    }

    bootstrap_effective_user() {
        printf 'root\n'
    }

    local saved_bootstrap_spawn_shell_action
    saved_bootstrap_spawn_shell_action="$(declare -f bootstrap_spawn_shell_action)"

    bootstrap_spawn_shell_action() {
        execution_trace+=("$1:$2:${BOOTSTRAP_TARGET_USER:-}:${BOOTSTRAP_TARGET_HOME:-}")
        return 0
    }

    local saved_target_user="${BOOTSTRAP_TARGET_USER:-}"
    local saved_target_home="${BOOTSTRAP_TARGET_HOME:-}"
    BOOTSTRAP_TARGET_USER=""
    BOOTSTRAP_TARGET_HOME=""
    execution_trace=()
    if ! bootstrap_user_action_requires_root_refusal "brew-tools" ""; then
        err "Expected root shell user actions to refuse when no non-root target is available"
        return 1
    fi
    BOOTSTRAP_TARGET_USER="$saved_target_user"
    BOOTSTRAP_TARGET_HOME="$saved_target_home"
    eval "$saved_bootstrap_spawn_shell_action"

    local saved_privilege="${BOOTSTRAP_ACTION_PRIVILEGES[brew-tools]:-}"
    unset 'BOOTSTRAP_ACTION_PRIVILEGES[brew-tools]'
    if BOOTSTRAP_FRONTEND_MODE=apply BOOTSTRAP_STATE_FILE="$temp_state" bootstrap_plan_compute "brew-tools" "" "" >/dev/null 2>&1; then
        err "Expected missing privilege metadata to be rejected"
        return 1
    fi
    BOOTSTRAP_ACTION_PRIVILEGES[brew-tools]="$saved_privilege"

    local saved_bootstrap_execute_action
    saved_bootstrap_execute_action="$(declare -f bootstrap_execute_action)"
    bootstrap_execute_action() {
        execution_trace+=("fail:$1")
        return 23
    }

    BOOTSTRAP_FRONTEND_MODE=apply
    BOOTSTRAP_STATE_FILE="$temp_state" bootstrap_plan_compute "brew-tools" "" ""
    execution_trace=()
    warning_trace=()
    set +e
    BOOTSTRAP_STATE_FILE="$temp_state" bootstrap_execute_plan >/dev/null 2>&1
    rc=$?
    set -e
    if [ "$rc" -eq 0 ]; then
        err "Expected failed actions to stop the bootstrap"
        return 1
    fi

    if [ "$rc" -ne 23 ]; then
        err "Expected bootstrap_execute_plan to return the failing action status"
        return 1
    fi

    if [ "${#execution_trace[@]}" -ne 1 ]; then
        err "Expected the failing action to run exactly once"
        return 1
    fi

    python3 - "$temp_state" <<'PY'
import json, sys

state = json.load(open(sys.argv[1], 'r', encoding='utf-8'))
assert state['last_status'] == 'partial_failure', state
assert state['failed_action'] == 'system-packages', state
assert state['completed_actions'] == [], state
PY

    if bootstrap_state_is_current \
        "$(bootstrap_catalog_hash)" \
        "alice" \
        "/home/alice" \
        "root" \
        "sudo-session" \
        "apply"; then
        err "Expected state reuse to fail across execution contexts"
        return 1
    fi

    eval "$saved_bootstrap_execute_action"

    baseline_hash="$(bootstrap_catalog_hash)"
    BOOTSTRAP_ACTION_PRIVILEGES[brew-tools]="mixed"
    mutated_hash="$(bootstrap_catalog_hash)"
    BOOTSTRAP_ACTION_PRIVILEGES[brew-tools]="user"
    if [ "$baseline_hash" = "$mutated_hash" ]; then
        err "Expected catalog hash to change when privilege metadata changes"
        return 1
    fi

    BOOTSTRAP_FRONTEND_MODE=apply
    BOOTSTRAP_STATE_FILE="$temp_state" bootstrap_plan_compute "brew-tools" "" ""
    if ! bootstrap_array_contains "system-packages" "${BOOTSTRAP_PLAN_ORDERED[@]}"; then
        err "Expected system-packages in dependency closure"
        return 1
    fi
    if ! bootstrap_array_contains "homebrew-bootstrap" "${BOOTSTRAP_PLAN_ORDERED[@]}"; then
        err "Expected homebrew-bootstrap in dependency closure"
        return 1
    fi
    if ! bootstrap_array_contains "brew-tools" "${BOOTSTRAP_PLAN_ORDERED[@]}"; then
        err "Expected brew-tools in dependency closure"
        return 1
    fi

    if BOOTSTRAP_STATE_FILE="$temp_state" bootstrap_plan_compute "brew-tools" "homebrew-bootstrap" "" >/dev/null 2>&1; then
        err "Expected skip validation to fail"
        return 1
    fi

    BOOTSTRAP_STATE_FILE="$temp_state" bootstrap_state_write \
        "$(bootstrap_catalog_hash)" \
        "success" \
        "" \
        0 \
        "" \
        "system-packages,homebrew-bootstrap" \
        "" \
        "" \
        "system-packages,homebrew-bootstrap,brew-tools" \
        "brew-tools" \
        "system-packages,homebrew-bootstrap"

    cp "$temp_state" "$temp_state_seed"

    BOOTSTRAP_STATE_FILE="$temp_state" bootstrap_plan_compute "brew-tools" "" ""
    if ! bootstrap_array_contains "brew-tools" "${BOOTSTRAP_PLAN_EXECUTE[@]}"; then
        err "Expected brew-tools to remain scheduled"
        return 1
    fi

    local plan_json
    plan_json="$(bootstrap_plan_emit_json)"
    python3 - "$plan_json" <<'PY'
import json, sys

plan = json.loads(sys.argv[1])
privileges = {a['id']: a['privilege'] for a in plan['actions']}
assert privileges['system-packages'] == 'elevated', privileges
assert privileges['homebrew-bootstrap'] == 'user', privileges
assert privileges['brew-tools'] == 'user', privileges
assert plan['context']['frontend'] == 'apply', plan['context']
PY

    local saved_sudo_function=""
    if declare -f sudo >/dev/null 2>&1; then
        saved_sudo_function="$(declare -f sudo)"
    fi

    local -a sudo_trace=()
    sudo() {
        sudo_trace=("$@")
        return 0
    }

    SUDO_USER="$real_user" \
    SUDO_UID="$real_uid" \
    SUDO_GID="$real_uid" \
    SUDO_COMMAND="sudo -u $real_user bash" \
    BOOTSTRAP_TARGET_USER="$real_user" \
    BOOTSTRAP_TARGET_HOME="/home/$real_user" \
    bootstrap_spawn_shell_action user "brew-tools" >/dev/null 2>&1 || true

    local saw_sudo_user_scrub=false
    local saw_sudo_uid_scrub=false
    local saw_sudo_gid_scrub=false
    local saw_sudo_command_scrub=false
    local saw_stale_sudo_assignment=false
    local arg
    for arg in "${sudo_trace[@]}"; do
        case "$arg" in
            SUDO_USER) saw_sudo_user_scrub=true ;;
            SUDO_UID) saw_sudo_uid_scrub=true ;;
            SUDO_GID) saw_sudo_gid_scrub=true ;;
            SUDO_COMMAND) saw_sudo_command_scrub=true ;;
            SUDO_*=*) saw_stale_sudo_assignment=true ;;
        esac
    done

    if [ "$saw_sudo_user_scrub" != true ] || [ "$saw_sudo_uid_scrub" != true ] || [ "$saw_sudo_gid_scrub" != true ] || [ "$saw_sudo_command_scrub" != true ] || [ "$saw_stale_sudo_assignment" = true ]; then
        err "Expected demoted child launch to scrub sudo provenance env"
        return 1
    fi

    local expected_trusted_path
    expected_trusted_path="$(bootstrap_trusted_child_path)"
    local saw_trusted_path=false
    local saw_raw_path=false
    for arg in "${sudo_trace[@]}"; do
        case "$arg" in
            PATH="$expected_trusted_path") saw_trusted_path=true ;;
            PATH=*) saw_raw_path=true ;;
        esac
    done

    if [ "$saw_trusted_path" != true ] || [ "$saw_raw_path" = true ]; then
        err "Expected demoted child launch to use a sanitized trusted PATH"
        return 1
    fi

    unset -f sudo 2>/dev/null || true
    if [ -n "$saved_sudo_function" ]; then
        eval "$saved_sudo_function"
    fi

    local temp_path_brew_dir temp_path_brew_bin temp_app_brew_dir temp_app_brew_bin
    temp_path_brew_dir="$temp_dir/nonstandard-prefix/bin"
    temp_path_brew_bin="$temp_path_brew_dir/brew"
    temp_app_brew_dir="$temp_dir/Applications/Homebrew.app/Contents/Resources/homebrew/bin"
    temp_app_brew_bin="$temp_app_brew_dir/brew"
    mkdir -p "$temp_path_brew_dir" "$temp_app_brew_dir"
    printf '#!/usr/bin/env bash\nexit 0\n' >"$temp_path_brew_bin"
    printf '#!/usr/bin/env bash\nexit 0\n' >"$temp_app_brew_bin"
    chmod +x "$temp_path_brew_bin" "$temp_app_brew_bin"

    local path_found=""
    path_found="$(PATH="$temp_path_brew_dir:${PATH:-/usr/bin:/bin}" BOOTSTRAP_TARGET_USER="$real_user" BOOTSTRAP_TARGET_HOME="$temp_dir/nonstandard-home" find_brew_binary)"
    if [ "$path_found" != "$temp_path_brew_bin" ]; then
        err "Expected brew discovery to respect a valid PATH install"
        return 1
    fi

    local saved_bootstrap_brew_candidate_paths
    saved_bootstrap_brew_candidate_paths="$(declare -f bootstrap_brew_candidate_paths)"
    bootstrap_brew_candidate_paths() {
        printf '%s\n' "$temp_app_brew_bin"
    }

    path_found="$(PATH="/usr/bin:/bin" BOOTSTRAP_TARGET_USER="$real_user" BOOTSTRAP_TARGET_HOME="$temp_dir/app-home" find_brew_binary)"
    if [ "$path_found" != "$temp_app_brew_bin" ]; then
        err "Expected brew discovery to accept a Homebrew.app-style install"
        return 1
    fi

    eval "$saved_bootstrap_brew_candidate_paths"

    local saved_bootstrap_brew_candidate_paths saved_bootstrap_path_owner_uid
    local temp_brew_user_dir temp_brew_system_dir user_brew_bin system_brew_bin
    temp_brew_user_dir="$temp_dir/user-home"
    temp_brew_system_dir="$temp_dir/system-prefix"
    user_brew_bin="$temp_brew_user_dir/.linuxbrew/bin/brew"
    system_brew_bin="$temp_brew_system_dir/usr/local/bin/brew"
    mkdir -p "$(dirname "$user_brew_bin")" "$(dirname "$system_brew_bin")"
    printf '#!/usr/bin/env bash\nexit 0\n' >"$user_brew_bin"
    printf '#!/usr/bin/env bash\nexit 0\n' >"$system_brew_bin"
    chmod +x "$user_brew_bin" "$system_brew_bin"

    saved_bootstrap_brew_candidate_paths="$(declare -f bootstrap_brew_candidate_paths)"
    saved_bootstrap_path_owner_uid="$(declare -f bootstrap_path_owner_uid)"
    bootstrap_brew_candidate_paths() {
        printf '%s\n' "$system_brew_bin" "$user_brew_bin"
    }
    bootstrap_path_owner_uid() {
        case "$1" in
            "$system_brew_bin"|"$temp_brew_system_dir/usr/local")
                printf '0\n'
                ;;
            "$user_brew_bin"|"$temp_brew_user_dir/.linuxbrew")
                printf '%s\n' "$real_uid"
                ;;
            *)
                printf '%s\n' "$real_uid"
                ;;
        esac
    }

    BOOTSTRAP_TARGET_USER="$real_user"
    BOOTSTRAP_TARGET_HOME="$temp_brew_user_dir"
    if [ "$(find_brew_binary)" != "$user_brew_bin" ]; then
        err "Expected brew selection to prefer the user-owned prefix"
        return 1
    fi

    bootstrap_path_owner_uid() {
        case "$1" in
            "$system_brew_bin"|"$temp_brew_system_dir/usr/local"|"$user_brew_bin"|"$temp_brew_user_dir/.linuxbrew")
                printf '0\n'
                ;;
            *)
                printf '%s\n' "$real_uid"
                ;;
        esac
    }

    if find_brew_binary >/dev/null 2>&1; then
        err "Expected wrong-owned brew prefixes to be rejected"
        return 1
    fi

    eval "$saved_bootstrap_brew_candidate_paths"
    eval "$saved_bootstrap_path_owner_uid"

    cat <<EOF | bootstrap_json_sign_canonical "$(bootstrap_integrity_load_secret)" >"$temp_malicious_plan"
{
  "schema_version": 1,
  "catalog_version": 1,
  "catalog_hash": "safe-catalog-hash",
  "context": {
    "target_user": "alice\\ncontext_execution_context=overwritten",
    "target_home": "/home/alice",
    "effective_user": "root",
    "execution_context": "root-shell",
    "frontend": "plan"
  },
  "selection": {
    "only": ["brew-tools"],
    "skip": [],
    "force": []
  },
  "ordered": ["system-packages", "homebrew-bootstrap", "brew-tools"],
  "execute": ["brew-tools"],
  "completed": ["system-packages", "homebrew-bootstrap"]
}
EOF

    bootstrap_plan_from_json_file "$temp_malicious_plan"
    if [ "$BOOTSTRAP_PLAN_CATALOG_HASH" != "safe-catalog-hash" ]; then
        err "Expected safe parsing to preserve the catalog hash"
        return 1
    fi

    if [ "$BOOTSTRAP_PLAN_CONTEXT_EXECUTION" != "root-shell" ]; then
        err "Expected safe parsing to preserve the execution context"
        return 1
    fi

    if [ "$BOOTSTRAP_PLAN_CONTEXT_TARGET_USER" != "$(printf 'alice\ncontext_execution_context=overwritten')" ]; then
        err "Expected safe parsing to preserve newline-bearing values"
        return 1
    fi

    rm -f "$temp_state"
    BOOTSTRAP_FRONTEND_MODE=apply BOOTSTRAP_STATE_FILE="$temp_state" bootstrap_plan_compute "brew-tools" "" ""
    execution_trace=()
    warning_trace=()
    bootstrap_spawn_shell_action() {
        execution_trace+=("$1:$2:${BOOTSTRAP_TARGET_USER:-}:${BOOTSTRAP_TARGET_HOME:-}")
        return 0
    }
    BOOTSTRAP_STATE_FILE="$temp_state" BOOTSTRAP_TARGET_USER="alice" BOOTSTRAP_TARGET_HOME="/home/alice" bootstrap_execute_plan
    if [ "$(bootstrap_join_csv "${execution_trace[@]}")" != "root:system-packages:alice:/home/alice,user:homebrew-bootstrap:alice:/home/alice,user:brew-tools:alice:/home/alice" ]; then
        err "Expected per-action privilege routing to keep user-owned actions out of root"
        return 1
    fi

    eval "$saved_bootstrap_spawn_shell_action"

    cp "$temp_state_seed" "$temp_state"
    BOOTSTRAP_STATE_FILE="$temp_state"
    BOOTSTRAP_FRONTEND_MODE=apply BOOTSTRAP_STATE_FILE="$temp_state" bootstrap_plan_compute "brew-tools" "" ""

    signed_plan_round_trip="$(bootstrap_plan_emit_json)"
    printf '%s\n' "$signed_plan_round_trip" >"$temp_plan"
    bootstrap_plan_from_json_file "$temp_plan" >/dev/null 2>&1 || {
        err "Expected signed plan to load cleanly"
        return 1
    }
    if [ -z "${BOOTSTRAP_PLAN_SIGNATURE:-}" ]; then
        err "Expected signed plan to carry a signature"
        return 1
    fi

    cp "$temp_plan" "$temp_plan.version"
    python3 - "$temp_plan.version" <<'PY'
import json, sys

path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as fh:
    data = json.load(fh)

data['schema_version'] = 2
with open(path, 'w', encoding='utf-8') as fh:
    json.dump(data, fh, indent=2, ensure_ascii=False)
    fh.write('\n')
PY

    if bootstrap_plan_from_json_file "$temp_plan.version" >/dev/null 2>&1; then
        err "Expected incompatible saved plan version to be rejected"
        return 1
    fi

    local temp_bad_state temp_bad_context
    temp_bad_state="$temp_dir/bootstrap-state-bad.json"
    temp_bad_context="$temp_dir/bootstrap-state-bad-context.json"

    printf '{"not": "json"' >"$temp_bad_state"
    if BOOTSTRAP_STATE_FILE="$temp_bad_state" bootstrap_state_completed_actions \
        "$(bootstrap_catalog_hash)" \
        "alice" \
        "/home/alice" \
        "root" \
        "root-shell" \
        "apply" >/dev/null 2>&1; then
        err "Expected malformed state to fail closed"
        return 1
    fi

    cp "$temp_state_seed" "$temp_bad_context"
    python3 - "$temp_bad_context" <<'PY'
import json, sys

path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as fh:
    data = json.load(fh)

data['context']['execution_context'] = 'sudo-session'
with open(path, 'w', encoding='utf-8') as fh:
    json.dump(data, fh, indent=2, ensure_ascii=False)
    fh.write('\n')
PY

    if BOOTSTRAP_STATE_FILE="$temp_bad_context" bootstrap_state_completed_actions \
        "$(bootstrap_catalog_hash)" \
        "alice" \
        "/home/alice" \
        "root" \
        "root-shell" \
        "apply" >/dev/null 2>&1; then
        err "Expected context-mismatched state to fail closed"
        return 1
    fi

    cp "$temp_plan" "$temp_tampered_plan"
    python3 - "$temp_tampered_plan" <<'PY'
import json, sys

path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as fh:
    data = json.load(fh)

data['execute'] = ['brew-tools', 'system-packages']
with open(path, 'w', encoding='utf-8') as fh:
    json.dump(data, fh, indent=2, ensure_ascii=False)
    fh.write('\n')
PY

    cp "$temp_state_seed" "$temp_state"
    execution_trace=()
    warning_trace=()
    set +e
    BOOTSTRAP_STATE_FILE="$temp_state" bootstrap_command_apply --plan "$temp_tampered_plan" >/dev/null 2>&1
    rc=$?
    set -e
    if [ "$rc" -eq 0 ]; then
        err "Expected tampered saved plan to be rejected"
        return 1
    fi
    if [ "${#execution_trace[@]}" -ne 0 ]; then
        err "Expected tampered saved plan rejection before any actions ran"
        return 1
    fi

    cp "$temp_state_seed" "$temp_state"
    if ! bootstrap_state_is_current \
        "$(bootstrap_catalog_hash)" \
        "alice" \
        "/home/alice" \
        "root" \
        "root-shell" \
        "apply"; then
        err "Expected signed state to load cleanly"
        return 1
    fi

    completed_trace=()
    local completed_trace_output
    if ! completed_trace_output="$(BOOTSTRAP_STATE_FILE="$temp_state" bootstrap_state_completed_actions \
        "$(bootstrap_catalog_hash)" \
        "alice" \
        "/home/alice" \
        "root" \
        "root-shell" \
        "apply")"; then
        err "Expected signed state replay to succeed"
        return 1
    fi

    while IFS= read -r action; do
        [ -n "$action" ] && completed_trace+=("$action")
    done <<<"$completed_trace_output"

    if [ "$(bootstrap_join_csv "${completed_trace[@]}")" != "system-packages,homebrew-bootstrap" ]; then
        err "Expected signed state round-trip to preserve the completed-actions list"
        return 1
    fi

    cp "$temp_plan" "$temp_stale_plan"
    python3 - "$temp_stale_plan" <<'PY'
import json, sys

path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as fh:
    data = json.load(fh)

data['catalog_hash'] = 'stale-catalog-hash'
with open(path, 'w', encoding='utf-8') as fh:
    json.dump(data, fh, indent=2, ensure_ascii=False)
    fh.write('\n')
PY
    cp "$temp_stale_plan" "$temp_stale_plan.resigned"
    bootstrap_json_sign_canonical "$(bootstrap_integrity_load_secret)" <"$temp_stale_plan" >"$temp_stale_plan.resigned"
    mv "$temp_stale_plan.resigned" "$temp_stale_plan"

    cp "$temp_state_seed" "$temp_state"
    execution_trace=()
    warning_trace=()
    set +e
    BOOTSTRAP_STATE_FILE="$temp_state" bootstrap_command_apply --plan "$temp_stale_plan" >/dev/null 2>&1
    rc=$?
    set -e
    if [ "$rc" -eq 0 ]; then
        err "Expected stale signed saved plan to be rejected"
        return 1
    fi
    if [ "${#execution_trace[@]}" -ne 0 ]; then
        err "Expected stale signed saved plan rejection before any actions ran"
        return 1
    fi

    cp "$temp_state_seed" "$temp_tampered_state"
    python3 - "$temp_tampered_state" <<'PY'
import json, sys

path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as fh:
    data = json.load(fh)

data['completed_actions'] = ['brew-tools']
with open(path, 'w', encoding='utf-8') as fh:
    json.dump(data, fh, indent=2, ensure_ascii=False)
    fh.write('\n')
PY

    if bootstrap_state_is_current \
        "$(bootstrap_catalog_hash)" \
        "alice" \
        "/home/alice" \
        "root" \
        "sudo-session" \
        "apply"; then
        err "Expected tampered state to be rejected"
        return 1
    fi

    if BOOTSTRAP_STATE_FILE="$temp_tampered_state" bootstrap_state_completed_actions \
        "$(bootstrap_catalog_hash)" \
        "alice" \
        "/home/alice" \
        "root" \
        "sudo-session" \
        "apply" >/dev/null 2>&1; then
        err "Expected tampered state completed-actions replay to fail closed"
        return 1
    fi

    execution_trace=()
    warning_trace=()
    set +e
    BOOTSTRAP_STATE_FILE="$temp_state" BOOTSTRAP_TARGET_USER="bob" BOOTSTRAP_TARGET_HOME="/home/bob" bootstrap_command_apply --plan "$temp_plan" >/dev/null 2>&1
    rc=$?
    set -e
    if [ "$rc" -eq 0 ]; then
        err "Expected saved plan identity mismatch to be rejected"
        return 1
    fi
    if [ "${#execution_trace[@]}" -ne 0 ]; then
        err "Expected saved plan identity mismatch rejection before any actions ran"
        return 1
    fi

    cp "$temp_state_seed" "$temp_wrong_frontend_state"
    python3 - "$temp_wrong_frontend_state" <<'PY'
import json, sys

path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as fh:
    data = json.load(fh)

data['context']['frontend'] = 'plan'
with open(path, 'w', encoding='utf-8') as fh:
    json.dump(data, fh, indent=2, ensure_ascii=False)
    fh.write('\n')
PY
    bootstrap_json_sign_canonical "$(bootstrap_integrity_load_secret)" <"$temp_wrong_frontend_state" >"$temp_wrong_frontend_state.resigned"
    mv "$temp_wrong_frontend_state.resigned" "$temp_wrong_frontend_state"

    if BOOTSTRAP_STATE_FILE="$temp_wrong_frontend_state" bootstrap_state_is_current \
        "$(bootstrap_catalog_hash)" \
        "alice" \
        "/home/alice" \
        "root" \
        "root-shell" \
        "apply" 2>/tmp/bootstrap-state-frontend-mismatch.out; then
        err "Expected state with mismatched frontend to be rejected"
        return 1
    fi
    if ! grep -q 'provenance:frontend:apply:plan' /tmp/bootstrap-state-frontend-mismatch.out; then
        err "Expected explicit frontend mismatch reason on state load"
        return 1
    fi

    if BOOTSTRAP_STATE_FILE="$temp_wrong_frontend_state" bootstrap_state_completed_actions \
        "$(bootstrap_catalog_hash)" \
        "alice" \
        "/home/alice" \
        "root" \
        "root-shell" \
        "apply" 2>/tmp/bootstrap-state-completed-frontend-mismatch.out >/dev/null; then
        err "Expected state completed-actions replay with mismatched frontend to be rejected"
        return 1
    fi
    if ! grep -q 'frontend' /tmp/bootstrap-state-completed-frontend-mismatch.out; then
        err "Expected explicit frontend mismatch reason on state completed-actions replay"
        return 1
    fi

    cp "$temp_plan" "$temp_wrong_frontend_plan"
    python3 - "$temp_wrong_frontend_plan" <<'PY'
import json, sys

path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as fh:
    data = json.load(fh)

data['context']['frontend'] = 'plan'
with open(path, 'w', encoding='utf-8') as fh:
    json.dump(data, fh, indent=2, ensure_ascii=False)
    fh.write('\n')
PY
    bootstrap_json_sign_canonical "$(bootstrap_integrity_load_secret)" <"$temp_wrong_frontend_plan" >"$temp_wrong_frontend_plan.resigned"
    mv "$temp_wrong_frontend_plan.resigned" "$temp_wrong_frontend_plan"

    bootstrap_plan_from_json_file "$temp_wrong_frontend_plan" >/dev/null 2>&1 || {
        err "Expected signed plan with mismatched frontend to load cleanly"
        return 1
    }
    if bootstrap_plan_enforce_context 2>/tmp/bootstrap-plan-frontend-mismatch.out; then
        err "Expected plan enforce-context to reject mismatched frontend"
        return 1
    fi
    if ! grep -q 'frontend' /tmp/bootstrap-plan-frontend-mismatch.out; then
        err "Expected explicit frontend mismatch reason on plan enforce-context"
        return 1
    fi

    BOOTSTRAP_TARGET_USER="$saved_bootstrap_target_user"
    BOOTSTRAP_TARGET_HOME="$saved_bootstrap_target_home"
    BOOTSTRAP_TEST_MODE_ACTIVE="$saved_bootstrap_test_mode_active"
    BOOTSTRAP_TEST_MODE="$saved_bootstrap_test_mode"

    rm -rf "$temp_dir"
    ok "Bootstrap planner self-test passed"
}

main() {
    bootstrap_parse_args "$@"
    if [ "${BOOTSTRAP_COMMAND:-apply}" = test ]; then
        BOOTSTRAP_TEST_MODE_ACTIVE=1
        BOOTSTRAP_TEST_MODE=1
    fi

    if [ "${BOOTSTRAP_COMMAND:-apply}" != controller ]; then
        echo ""
        printf '\033[1m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n'
        printf '\033[1m  Dotfiles Bootstrap\033[0m\n'
        printf '\033[1m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n\n'
        bootstrap_show_startup_context "${BOOTSTRAP_COMMAND:-apply}"
        echo
    fi

    case "${1:-}" in
        plan|apply|list|controller|test|help|-h|--help)
            ;;
        "")
            set -- apply
            ;;
        *)
            set -- apply "$@"
            ;;
    esac

    case "${1:-}" in
        plan)
            shift
            bootstrap_command_plan "$@"
            ;;
        apply)
            shift
            bootstrap_command_apply "$@"
            ;;
        list)
            shift
            bootstrap_command_list "$@"
            ;;
        controller)
            shift
            bootstrap_command_controller "$@"
            ;;
        test)
            shift
            bootstrap_self_test "$@"
            ;;
        help|-h|--help)
            cat <<'EOF'
Usage: bootstrap/install.sh [plan|apply|list|controller|test] [selectors]

Commands:
  plan   Compute a deterministic bootstrap plan
  apply  Compute and execute a bootstrap plan (default)
  list   List the catalog and current advisory status
  controller  Respond to an optional Go controller handshake request
  test   Run planner self-checks

Selectors:
  --only ACTION[,ACTION...]
  --skip ACTION[,ACTION...]
  --force ACTION[,ACTION...]
  --format text|json
  --plan FILE
EOF
            ;;
    esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
