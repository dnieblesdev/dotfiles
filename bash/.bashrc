# ──────────────────────────────────────────────
# .bashrc principal — solo orquesta, no implementa
# ──────────────────────────────────────────────

# Si no es interactivo, salir
case $- in
    *i*) ;;
      *) return;;
esac

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

source ~/.dotfiles/bash/config
source ~/.dotfiles/bash/prompt
source ~/.dotfiles/bash/aliases
source ~/.dotfiles/bash/completions
source ~/.dotfiles/bash/functions

# === 3. Variables de entorno ===

source ~/.dotfiles/env/paths
source ~/.dotfiles/env/nvm

# === 4. Git ===

[ -f ~/.gitconfig ] && true  # git lo lee solo

# === 5. Por SO ===

if is_wsl; then
    source ~/.dotfiles/wsl/env
    source ~/.dotfiles/wsl/functions
elif is_linux; then
    source ~/.dotfiles/linux/env
    source ~/.dotfiles/linux/functions
fi
