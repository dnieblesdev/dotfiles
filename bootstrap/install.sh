#!/usr/bin/env bash
# install.sh — Bootstrap completo de dotfiles
# Uso: curl -fsSL https://raw.githubusercontent.com/dnieblesdev/dotfiles/main/bootstrap/install.sh | bash
# O local: ~/.dotfiles/bootstrap/install.sh

set -euo pipefail

DOTFILES_REPO="https://github.com/dnieblesdev/dotfiles.git"
DOTFILES_DIR="$HOME/.dotfiles"
BACKUP_DIR="$HOME/.dotfiles-backup-$(date +%Y%m%d-%H%M%S)"

# ── Utils ──
info()  { echo -e "  \033[36m→\033[0m $1"; }
ok()    { echo -e "  \033[32m✓\033[0m $1"; }
warn()  { echo -e "  \033[33m⚠\033[0m $1"; }
err()   { echo -e "  \033[31m✗\033[0m $1"; }

apt_install_required() {
    sudo apt install -y -qq "$@"
}

apt_install_optional() {
    local pkg
    for pkg in "$@"; do
        if dpkg -s "$pkg" >/dev/null 2>&1; then
            info "$pkg ya instalado"
            continue
        fi

        info "Instalando $pkg..."
        if sudo apt install -y -qq "$pkg" >/dev/null 2>&1; then
            ok "$pkg instalado"
        else
            warn "No se pudo instalar $pkg desde apt. Continuando."
        fi
    done
}

install_starship_best_effort() {
    if command -v starship >/dev/null 2>&1; then
        info "starship ya instalado"
        return 0
    fi

    if command -v apt >/dev/null 2>&1 && apt-cache show starship >/dev/null 2>&1; then
        info "Instalando starship desde apt..."
        sudo apt install -y -qq starship >/dev/null 2>&1 || warn "No se pudo instalar starship desde apt."
    fi

    if ! command -v starship >/dev/null 2>&1; then
        info "Instalando starship con el instalador oficial..."
        if curl -fsSL https://starship.rs/install.sh | sh -s -- -y >/dev/null 2>&1; then
            ok "starship instalado"
        else
            warn "No se pudo instalar starship. Podés instalarlo manualmente luego."
        fi
    fi
}

install_tldr_best_effort() {
    if command -v tldr >/dev/null 2>&1 || command -v tealdeer >/dev/null 2>&1; then
        info "tldr/tealdeer ya instalado"
        return 0
    fi

    if sudo apt install -y -qq tldr >/dev/null 2>&1; then
        ok "tldr instalado"
    elif sudo apt install -y -qq tealdeer >/dev/null 2>&1; then
        ok "tealdeer instalado"
    else
        warn "No se pudo instalar tldr ni tealdeer desde apt. Continuando."
    fi
}

# Detectar SO
is_wsl()     { grep -qi microsoft /proc/version 2>/dev/null; }
is_linux()   { [ "$(uname)" = "Linux" ] && ! is_wsl; }

echo ""
echo -e "\033[1m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo -e "\033[1m  Dotfiles Bootstrap\033[0m"
echo -e "\033[1m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo ""

# ── 1. Paquetes base del sistema ──
echo -e "\033[1m[1/5] Paquetes del sistema\033[0m"

if is_linux || is_wsl; then
    if command -v apt &>/dev/null; then
        info "Actualizando apt..."
        sudo apt update -qq
        apt_install_required git curl unzip build-essential
        ok "Paquetes base instalados"

        info "Instalando herramientas interactivas de terminal..."
        apt_install_optional zsh fzf bat ripgrep fd-find zoxide eza
        install_tldr_best_effort
        install_starship_best_effort

        if command -v batcat >/dev/null 2>&1 && ! command -v bat >/dev/null 2>&1; then
            info "Ubuntu expone bat como batcat; los aliases de Zsh lo manejan."
        fi

        if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
            info "Ubuntu expone fd como fdfind; los aliases y p() lo manejan."
        fi
    else
        warn "No se detectó apt. Instalá git, curl, unzip, zsh, starship, zoxide, fzf, bat, eza, ripgrep, fd y tldr manualmente."
    fi
fi

# ── 2. Clonar dotfiles ──
echo ""
echo -e "\033[1m[2/5] Clonando dotfiles\033[0m"

if [ -d "$DOTFILES_DIR" ]; then
    info "~/.dotfiles/ ya existe. Actualizando..."
    git -C "$DOTFILES_DIR" pull --ff-only 2>/dev/null || warn "No se pudo actualizar (cambios locales?)"
else
    git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
    ok "Clonado en $DOTFILES_DIR"
fi

# ── 3. Backup de dotfiles existentes ──
echo ""
echo -e "\033[1m[3/5] Backup de config actual\033[0m"

NEEDS_BACKUP=false
for f in .bashrc .zshrc .profile .gitconfig; do
    if [ -f "$HOME/$f" ] && [ ! -L "$HOME/$f" ]; then
        NEEDS_BACKUP=true
        break
    fi
done

if [ "$NEEDS_BACKUP" = true ]; then
    mkdir -p "$BACKUP_DIR"
    for f in .bashrc .zshrc .profile .gitconfig; do
        if [ -f "$HOME/$f" ] && [ ! -L "$HOME/$f" ]; then
            cp "$HOME/$f" "$BACKUP_DIR/$f"
            info "Respaldado $HOME/$f → $BACKUP_DIR/$f"
        fi
    done
    ok "Backup en $BACKUP_DIR"
else
    info "No hay archivos originales que respaldar (ya son symlinks o no existen)"
fi

# ── 4. Linkear dotfiles ──
echo ""
echo -e "\033[1m[4/5] Instalando dotfiles\033[0m"

chmod +x "$DOTFILES_DIR/bootstrap/dotlink"
"$DOTFILES_DIR/bootstrap/dotlink" bash git zsh config

if is_wsl; then
    "$DOTFILES_DIR/bootstrap/dotlink" wsl
elif is_linux; then
    "$DOTFILES_DIR/bootstrap/dotlink" linux
fi

ok "Dotfiles instalados"

# ── 5. Runtimes opcionales ──
echo ""
echo -e "\033[1m[5/5] Runtimes\033[0m"

# NVM
if [ ! -d "$HOME/.nvm" ]; then
    info "Instalando nvm..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
    ok "nvm instalado"
else
    info "nvm ya instalado"
fi

# Rust
if ! command -v rustc &>/dev/null; then
    info "Instalando Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y 2>/dev/null
    ok "Rust instalado"
else
    info "Rust ya instalado"
fi

# Flutter (solo instrucción)
if [ ! -d "$HOME/development/flutter" ]; then
    warn "Flutter no detectado. Si lo necesitás: https://docs.flutter.dev/get-started/install/linux"
fi

# ── Fin ──
echo ""
echo -e "\033[1m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo -e "\033[1m  ✅ Bootstrap completado\033[0m"
echo -e "\033[1m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo ""
echo "  Cerra y abrí la terminal para que los cambios surtan efecto."
echo "  Para usar Zsh como shell por defecto, revisá primero: chsh -s \"$(command -v zsh || echo /usr/bin/zsh)\""
echo "  El bootstrap NO cambia tu shell automáticamente."
echo "  Si algo no funciona, corré: dotlink --list"
echo ""
