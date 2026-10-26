# ──────────────────────────────────────────────
# Zsh entrypoint — optional interactive layer
# ──────────────────────────────────────────────

# Stop early for non-interactive shells.
case $- in
    *i*) ;;
      *) return ;;
esac

# :A resolves symlinks, including a dotlink entrypoint in another HOME.
DOTFILES_ROOT="${${(%):-%x}:A:h:h}"

is_wsl() {
    grep -qi microsoft /proc/version 2>/dev/null
}

is_linux() {
    [ "$(uname)" = "Linux" ] && ! is_wsl
}

# Shared environment stays shell-agnostic where possible.
source "$DOTFILES_ROOT/env/paths"
source "$DOTFILES_ROOT/env/nvm"

if is_wsl; then
    source "$DOTFILES_ROOT/wsl/env"
elif is_linux; then
    source "$DOTFILES_ROOT/linux/env"
fi

source "$DOTFILES_ROOT/zsh/completions"
source "$DOTFILES_ROOT/zsh/aliases"
source "$DOTFILES_ROOT/zsh/functions"
source "$DOTFILES_ROOT/zsh/tools"

# Use an available installation; never assume or install Linuxbrew.
if command -v brew >/dev/null 2>&1; then
    eval "$(brew shellenv zsh)"
fi

# bun completions
[ -s "${BUN_INSTALL:-$HOME/.bun}/_bun" ] && source "${BUN_INSTALL:-$HOME/.bun}/_bun"

# bun
export BUN_INSTALL="${BUN_INSTALL:-$HOME/.bun}"
[ ! -d "$BUN_INSTALL/bin" ] || path_prepend "$BUN_INSTALL/bin"

# Activate after Homebrew, NVM, and Bun so mise-managed tools and shims keep precedence.
if command -v mise >/dev/null 2>&1; then
    path_prepend "$HOME/.local/share/mise/shims"
    eval "$(mise activate zsh)"
fi

# Priorizar ejecutables locales de WSL y eliminar entradas duplicadas
typeset -U path PATH
path=("$HOME/.local/bin" $path)
export PATH
