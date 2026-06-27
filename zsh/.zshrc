# ──────────────────────────────────────────────
# Zsh entrypoint — optional interactive layer
# ──────────────────────────────────────────────

# Stop early for non-interactive shells.
case $- in
    *i*) ;;
      *) return ;;
esac

is_wsl() {
    grep -qi microsoft /proc/version 2>/dev/null
}

is_linux() {
    [ "$(uname)" = "Linux" ] && ! is_wsl
}

# Shared environment stays shell-agnostic where possible.
[ -f "$HOME/.dotfiles/env/paths" ] && source "$HOME/.dotfiles/env/paths"
[ -f "$HOME/.dotfiles/env/nvm" ] && source "$HOME/.dotfiles/env/nvm"

if is_wsl && [ -f "$HOME/.dotfiles/wsl/env" ]; then
    source "$HOME/.dotfiles/wsl/env"
elif is_linux && [ -f "$HOME/.dotfiles/linux/env" ]; then
    source "$HOME/.dotfiles/linux/env"
fi

source "$HOME/.dotfiles/zsh/completions"
source "$HOME/.dotfiles/zsh/aliases"
source "$HOME/.dotfiles/zsh/functions"
source "$HOME/.dotfiles/zsh/tools"
