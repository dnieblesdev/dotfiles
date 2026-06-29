#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/lib/util.sh"
source "$SCRIPT_DIR/lib/catalog.sh"
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
    elif command_exists sudo; then
        sudo "$@"
    else
        return 127
    fi
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

brew_candidates() {
    printf '%s\n' \
        "$HOME/.linuxbrew/bin/brew" \
        "/home/linuxbrew/.linuxbrew/bin/brew" \
        "/opt/homebrew/bin/brew" \
        "/usr/local/bin/brew"
}

find_brew_binary() {
    if command_exists brew; then
        command -v brew
        return 0
    fi

    local candidate
    while IFS= read -r candidate; do
        if [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done <<EOF
$(brew_candidates)
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

bootstrap_homebrew() {
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
        homebrew)
            bootstrap_homebrew
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

bootstrap_parse_args() {
    BOOTSTRAP_COMMAND="apply"
    BOOTSTRAP_FORMAT="text"
    BOOTSTRAP_PLAN_FILE=""
    local -a only=()
    local -a skip=()
    local -a force=()
    local -a positional=()

    case "${1:-}" in
        plan|apply|list|test|help|-h|--help)
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

    BOOTSTRAP_ONLY_CSV="$(bootstrap_join_csv "${only[@]}")"
    BOOTSTRAP_SKIP_CSV="$(bootstrap_join_csv "${skip[@]}")"
    BOOTSTRAP_FORCE_CSV="$(bootstrap_join_csv "${force[@]}")"
}

bootstrap_execute_plan() {
    local action rc
    local -a completed=("${BOOTSTRAP_PLAN_COMPLETED[@]}")

    for action in "${BOOTSTRAP_PLAN_EXECUTE[@]}"; do
        printf '\n\033[1m[%s]\033[0m\n' "$action"
        if bootstrap_run_action "$action"; then
            if ! bootstrap_array_contains "$action" "${completed[@]}"; then
                completed+=("$action")
            fi
            bootstrap_state_write \
                "$BOOTSTRAP_CATALOG_HASH" \
                "partial_success" \
                "" \
                0 \
                "" \
                "$BOOTSTRAP_ONLY_CSV" \
                "$BOOTSTRAP_SKIP_CSV" \
                "$BOOTSTRAP_FORCE_CSV" \
                "$(bootstrap_join_csv "${BOOTSTRAP_PLAN_ORDERED[@]}")" \
                "$(bootstrap_join_csv "${BOOTSTRAP_PLAN_EXECUTE[@]}")" \
                "$(bootstrap_join_csv "${completed[@]}")"
            continue
        fi

        rc=$?
        bootstrap_state_write \
            "$BOOTSTRAP_CATALOG_HASH" \
            "partial_failure" \
            "$action" \
            "$rc" \
            "Action failed" \
            "$BOOTSTRAP_ONLY_CSV" \
            "$BOOTSTRAP_SKIP_CSV" \
            "$BOOTSTRAP_FORCE_CSV" \
            "$(bootstrap_join_csv "${BOOTSTRAP_PLAN_ORDERED[@]}")" \
            "$(bootstrap_join_csv "${BOOTSTRAP_PLAN_EXECUTE[@]}")" \
            "$(bootstrap_join_csv "${completed[@]}")"
        return "$rc"
    done

    bootstrap_state_write \
        "$BOOTSTRAP_CATALOG_HASH" \
        "success" \
        "" \
        0 \
        "" \
        "$BOOTSTRAP_ONLY_CSV" \
        "$BOOTSTRAP_SKIP_CSV" \
        "$BOOTSTRAP_FORCE_CSV" \
        "$(bootstrap_join_csv "${BOOTSTRAP_PLAN_ORDERED[@]}")" \
        "$(bootstrap_join_csv "${BOOTSTRAP_PLAN_EXECUTE[@]}")" \
        "$(bootstrap_join_csv "${completed[@]}")"
}

bootstrap_command_plan() {
    bootstrap_parse_args "$@"

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

        BOOTSTRAP_CATALOG_HASH="$current_hash"
        BOOTSTRAP_ONLY_CSV="$(bootstrap_join_csv "${BOOTSTRAP_PLAN_ONLY[@]}")"
        BOOTSTRAP_SKIP_CSV="$(bootstrap_join_csv "${BOOTSTRAP_PLAN_SKIP[@]}")"
        BOOTSTRAP_FORCE_CSV="$(bootstrap_join_csv "${BOOTSTRAP_PLAN_FORCE[@]}")"
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

    case "$BOOTSTRAP_FORMAT" in
        json) bootstrap_list_emit_json ;;
        text|*) bootstrap_list_emit_text ;;
    esac
}

bootstrap_self_test() {
    local temp_dir temp_state temp_plan temp_stale_plan
    local -a executed_actions=()
    temp_dir="$(mktemp -d)"
    temp_state="$temp_dir/bootstrap-state.json"
    temp_plan="$temp_dir/bootstrap-plan.json"
    temp_stale_plan="$temp_dir/bootstrap-plan-stale.json"

    bootstrap_run_action() {
        executed_actions+=("$1")
        return 0
    }

    BOOTSTRAP_STATE_FILE="$temp_state" bootstrap_plan_compute "brew-tools" "" ""
    if ! bootstrap_array_contains "system-packages" "${BOOTSTRAP_PLAN_ORDERED[@]}"; then
        err "Expected system-packages in dependency closure"
        return 1
    fi
    if ! bootstrap_array_contains "homebrew" "${BOOTSTRAP_PLAN_ORDERED[@]}"; then
        err "Expected homebrew in dependency closure"
        return 1
    fi
    if ! bootstrap_array_contains "brew-tools" "${BOOTSTRAP_PLAN_ORDERED[@]}"; then
        err "Expected brew-tools in dependency closure"
        return 1
    fi

    if BOOTSTRAP_STATE_FILE="$temp_state" bootstrap_plan_compute "brew-tools" "homebrew" "" >/dev/null 2>&1; then
        err "Expected skip validation to fail"
        return 1
    fi

    BOOTSTRAP_STATE_FILE="$temp_state" bootstrap_state_write \
        "$(bootstrap_catalog_hash)" \
        "success" \
        "" \
        0 \
        "" \
        "system-packages,homebrew" \
        "" \
        "" \
        "system-packages,homebrew,brew-tools" \
        "brew-tools" \
        "system-packages,homebrew"

    BOOTSTRAP_STATE_FILE="$temp_state" bootstrap_plan_compute "brew-tools" "" ""
    if ! bootstrap_array_contains "brew-tools" "${BOOTSTRAP_PLAN_EXECUTE[@]}"; then
        err "Expected brew-tools to remain scheduled"
        return 1
    fi

    cat >"$temp_plan" <<EOF
{
  "schema_version": 1,
  "catalog_version": 1,
  "catalog_hash": $(bootstrap_json_quote "$(bootstrap_catalog_hash)"),
  "selection": {
    "only": ["brew-tools"],
    "skip": [],
    "force": []
  },
  "ordered": ["system-packages", "homebrew", "brew-tools"],
  "execute": ["brew-tools"],
  "completed": ["system-packages", "homebrew"]
}
EOF

    executed_actions=()
    BOOTSTRAP_STATE_FILE="$temp_state" bootstrap_command_apply --plan "$temp_plan" >/dev/null 2>&1
    if [ "$(bootstrap_join_csv "${executed_actions[@]}")" != "brew-tools" ]; then
        err "Expected saved plan execution to honor the persisted execute list"
        return 1
    fi

    python3 - "$temp_state" <<'PY'
import json, sys

state = json.load(open(sys.argv[1], 'r', encoding='utf-8'))
assert state['selection']['only'] == ['brew-tools'], state['selection']
assert state['plan']['ordered'] == ['system-packages', 'homebrew', 'brew-tools'], state['plan']
assert state['plan']['execute'] == ['brew-tools'], state['plan']
assert state['completed_actions'] == ['system-packages', 'homebrew', 'brew-tools'], state['completed_actions']
PY

    cat >"$temp_stale_plan" <<EOF
{
  "schema_version": 1,
  "catalog_version": 1,
  "catalog_hash": "stale-catalog-hash",
  "selection": {
    "only": ["brew-tools"],
    "skip": [],
    "force": []
  },
  "ordered": ["system-packages", "homebrew", "brew-tools"],
  "execute": ["brew-tools"],
  "completed": ["system-packages", "homebrew"]
}
EOF

    executed_actions=()
    if BOOTSTRAP_STATE_FILE="$temp_state" bootstrap_command_apply --plan "$temp_stale_plan" >/dev/null 2>&1; then
        err "Expected stale saved plan to be rejected"
        return 1
    fi
    if [ -n "$(bootstrap_join_csv "${executed_actions[@]}")" ]; then
        err "Expected stale saved plan rejection before any actions ran"
        return 1
    fi

    rm -rf "$temp_dir"
    ok "Bootstrap planner self-test passed"
}

main() {
    echo ""
    printf '\033[1m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n'
    printf '\033[1m  Dotfiles Bootstrap\033[0m\n'
    printf '\033[1m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n\n'

    case "${1:-}" in
        plan|apply|list|test|help|-h|--help)
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
        test)
            shift
            bootstrap_self_test "$@"
            ;;
        help|-h|--help)
            cat <<'EOF'
Usage: bootstrap/install.sh [plan|apply|list|test] [selectors]

Commands:
  plan   Compute a deterministic bootstrap plan
  apply  Compute and execute a bootstrap plan (default)
  list   List the catalog and current advisory status
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
