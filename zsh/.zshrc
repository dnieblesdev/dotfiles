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

# Unwind an existing official activation before repo/NVM PATH mutations.
if (( $+functions[_mise_hook] )) && command -v mise >/dev/null 2>&1; then
    mise deactivate
fi

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
# Keep all repository PATH edits ahead of mise activation.
typeset -U path PATH
path=("$HOME/.local/bin" $path)
export PATH

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

# mise activation is repeatable: its generated code replaces its own hooks.
if command -v mise >/dev/null 2>&1; then
    eval "$(mise activate zsh)"
fi
