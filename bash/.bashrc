# ──────────────────────────────────────────────
# .bashrc principal — solo orquesta, no implementa
# ──────────────────────────────────────────────

# Si no es interactivo, salir
case $- in
    *i*) ;;
      *) return;;
esac

# Resolve the linked entrypoint, not the checkout's installation directory.
DOTFILES_ROOT="$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.."
DOTFILES_ROOT="$(cd -- "$DOTFILES_ROOT" && pwd -P)"

# Unwind an existing official activation before repo/NVM PATH mutations.
if declare -F _mise_hook >/dev/null && command -v mise >/dev/null 2>&1; then
    mise deactivate
fi

# === 1. Funciones de detección de SO (van primero) ===

is_wsl() {
    grep -qi microsoft /proc/version 2>/dev/null
}

is_linux() {
    [ "$(uname)" = "Linux" ] && ! is_wsl
}

is_windows() {
    case "$OSTYPE" in
        msys|cygwin) return 0 ;;
        *) return 1 ;;
    esac
}

# === 2. Config genérica del shell ===

source "$DOTFILES_ROOT/bash/config"
source "$DOTFILES_ROOT/bash/prompt"
source "$DOTFILES_ROOT/bash/aliases"
source "$DOTFILES_ROOT/bash/completions"
source "$DOTFILES_ROOT/bash/functions"

# === 3. Variables de entorno ===

source "$DOTFILES_ROOT/env/paths"
source "$DOTFILES_ROOT/env/nvm"

# WSL interop: allow xdg-open to detect WSL and launch Windows URL handlers.
case "$OSTYPE" in
    linux-gnu*)
        if grep -qi microsoft /proc/version 2>/dev/null; then
            path_prepend "/mnt/c/Windows/System32"
            path_prepend "/mnt/c/Windows"
        fi
        ;;
esac

# Initialize optional tools after repository PATH updates so mise retains precedence.
if command -v zoxide >/dev/null 2>&1 && ! declare -F __zoxide_z >/dev/null; then
    eval "$(zoxide init bash)"
fi
# mise's generated activation removes/replaces its own hooks before installing them.
if command -v mise >/dev/null 2>&1; then
    eval "$(mise activate bash)"
fi

# === 4. Git ===

[ -f ~/.gitconfig ] && true  # git lo lee solo

# === 5. Por SO ===

if is_wsl; then
    source "$DOTFILES_ROOT/wsl/env"
    source "$DOTFILES_ROOT/wsl/functions"
elif is_linux; then
    source "$DOTFILES_ROOT/linux/env"
    source "$DOTFILES_ROOT/linux/functions"
fi
