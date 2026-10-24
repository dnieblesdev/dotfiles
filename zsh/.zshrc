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

eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv zsh)"

# bun completions
[ -s "/home/dniebles/.bun/_bun" ] && source "/home/dniebles/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

# Activate after Homebrew, NVM, and Bun so mise-managed tools and shims keep precedence.
if command -v mise >/dev/null 2>&1; then
    path_prepend "$HOME/.local/share/mise/shims"
    eval "$(mise activate zsh)"
fi

# Priorizar ejecutables locales de WSL y eliminar entradas duplicadas
typeset -U path PATH
path=("$HOME/.local/bin" $path)
export PATH
