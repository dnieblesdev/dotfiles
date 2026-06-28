#!/usr/bin/env bash

set -euo pipefail

DOTFILES_REPO="https://github.com/dnieblesdev/dotfiles.git"
DOTFILES_DIR="$HOME/.dotfiles"
BACKUP_DIR="$HOME/.dotfiles-backup-$(date +%Y%m%d-%H%M%S)"

APT_PACKAGES=(git curl wget openssh-client build-essential unzip tar file procps)
PACMAN_PACKAGES=(git curl wget openssh base-devel unzip tar file procps-ng)
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

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

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
    grep -qi microsoft /proc/version 2>/dev/null
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
        [ -x "$candidate" ] && {
            printf '%s\n' "$candidate"
            return 0
        }
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

    eval "$("$brew_bin" shellenv)"

    if ! command_exists brew; then
        warn "brew shellenv did not place brew on PATH. Skipping brew-managed tools."
        return 1
    fi

    ok "Homebrew ready"
    return 0
}

install_brew_formula() {
    local label="$1"
    local formula="${2:-$1}"

    if ! command_exists brew; then
        warn "Skipping $label: Homebrew is unavailable"
        return 0
    fi

    if brew list "$formula" >/dev/null 2>&1; then
        info "$label already installed"
        return 0
    fi

    info "Installing $label with Homebrew"
    if brew install "$formula" >/dev/null 2>&1; then
        if brew list "$formula" >/dev/null 2>&1; then
            ok "$label installed"
        else
            warn "Homebrew finished but $label could not be verified"
        fi
    else
        warn "Could not install $label with Homebrew. Continuing without it."
    fi
}

install_brew_dev_tools() {
    if ! command_exists brew; then
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

install_runtimes() {
    install_nvm_runtime
    install_uv_runtime
    install_rustup_runtime

    if [ ! -d "$HOME/development/flutter" ]; then
        warn "Flutter not detected. If you need it: https://docs.flutter.dev/get-started/install/linux"
    fi
}

main() {
    echo ""
    printf '\033[1m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n'
    printf '\033[1m  Dotfiles Bootstrap\033[0m\n'
    printf '\033[1m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n\n'

    printf '\033[1m[1/5] System packages\033[0m\n'
    local package_manager
    package_manager="$(detect_package_manager || true)"
    install_system_packages "$package_manager"

    echo ""
    printf '\033[1m[2/5] Homebrew bootstrap\033[0m\n'
    if ! bootstrap_homebrew; then
        warn "Homebrew is not ready; brew-managed tools will be skipped"
    fi

    echo ""
    printf '\033[1m[3/5] Brew-managed developer tools\033[0m\n'
    install_brew_dev_tools

    echo ""
    printf '\033[1m[4/5] Dotfiles setup\033[0m\n'
    clone_or_update_dotfiles
    backup_existing_shell_files
    link_dotfiles

    echo ""
    printf '\033[1m[5/5] Runtimes\033[0m\n'
    install_runtimes

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

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
