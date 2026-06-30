# Dotfiles

Personal dotfiles for a modular shell development environment across WSL and native Linux.

This repository keeps shell configuration, environment paths, Git configuration, and bootstrap scripts organized by responsibility instead of keeping everything in one large shell file.

Bash remains the compatibility/base layer. Zsh is an optional interactive personalization layer with lightweight tools and no Oh My Zsh dependency.

## Current status

The bootstrap is shell-first, supports selective reruns, and keeps advisory state under `$XDG_STATE_HOME`.
The remaining security hardening work is documented in [`docs/installer.md`](docs/installer.md).
An optional Go controller can present shell-owned choices, but it is never required for bootstrap.

## Quick install

Clone the repository:

```bash
git clone https://github.com/dnieblesdev/dotfiles.git ~/.dotfiles
```

Link the active dotfiles:

```bash
~/.dotfiles/installer/dotlink bash git
```

Link the optional Zsh interactive layer and Starship config:

```bash
~/.dotfiles/installer/dotlink zsh config
```

Or run the full bootstrap:

```bash
~/.dotfiles/installer/install.sh
```

## Bootstrap order

The bootstrap now follows a strict split:

1. System packages from the distro package manager only (`apt` or `pacman`): `git`, `curl`, `wget`, `openssh`, build tools, `unzip`, and `tar`
2. Homebrew bootstrap with explicit detection, install, verification, and `brew shellenv`
3. Brew-managed developer tools for Linux/WSL: `eza`, `bat`, `fd`, `ripgrep`, `fzf`, `zoxide`, `starship`, `neovim`, `lazygit`, `bottom`, `dua`, and `tldr`
4. Runtime managers kept separate from Brew: `nvm`, `uv`, and `rustup`

If Homebrew is missing or fails to install, the bootstrap warns clearly and skips only the brew-managed layer.
The optional Go frontend uses a versioned handshake and falls back to the shell path when it is missing or outdated.

Install `zsh` separately if your distro does not already provide it.

Privilege handling is per action: the bootstrap warns once when running as root, requests explicit confirmation, and keeps Brew-managed apps/tools user-owned by default. System-package installs are the only elevated phase by design.

## Structure

| Path | Purpose |
|------|---------|
| `bash/` | Compatibility/base Bash entrypoint, aliases, prompt, completions, shell config, and functions |
| `zsh/` | Optional interactive Zsh layer: aliases, functions, completions, and tool initialization |
| `config/` | XDG config files linked under `$HOME`, including Starship |
| `env/` | Shared environment setup such as PATH, NVM, Rust, Flutter, Java, and Android SDK |
| `git/` | Git configuration linked into `$HOME` |
| `wsl/` | WSL-specific environment and functions |
| `linux/` | Native Linux-specific environment and functions |
| `installer/` | Installation and linking scripts |

## dotlink

`dotlink` is a small local linker inspired by GNU Stow, but intentionally limited to this repository's needs.

It links dotfiles from module folders into `$HOME`:

```bash
~/.dotfiles/installer/dotlink bash git
```

Useful commands:

```bash
~/.dotfiles/installer/dotlink --list
~/.dotfiles/installer/dotlink --dry-run bash git
~/.dotfiles/installer/dotlink --delete bash
```

`dotlink` also supports nested dot directories such as `.config/`. It creates the parent directory in `$HOME` as a real directory, then links children individually, so `config/.config/starship.toml` links to `~/.config/starship.toml` without symlinking the whole `~/.config` directory.

## Zsh interactive layer

The Zsh layer is intentionally small and transparent. It does not use Oh My Zsh.

The bootstrap installs the common interactive tools via Homebrew when available:

- `starship`
- `zoxide`
- `fzf`
- `bat` / `batcat`
- `eza`
- `ripgrep`
- `fd` / `fdfind`
- `tldr` via `tealdeer`

Runtime managers stay separate from Brew:

- `nvm`
- `uv`
- `rustup`

Install and link everything with the bootstrap:

```bash
~/.dotfiles/installer/install.sh
```

Or link only the Zsh layer after cloning:

```bash
~/.dotfiles/installer/dotlink zsh config
```

The expected links are:

```text
~/.zshrc                 -> ~/.dotfiles/zsh/.zshrc
~/.config/starship.toml  -> ~/.dotfiles/config/.config/starship.toml
```

The bootstrap does not change the default shell automatically. After reviewing the linked config, switch manually if desired:

```bash
chsh -s "$(command -v zsh)"
```

### Project picker

Zsh includes a `p` function that reads `$WORKSPACE`, lists first-level projects with `fd`/`fdfind`, lets you choose with `fzf`, and changes into the selected directory. `zoxide` learns from normal directory changes through its shell hook.

## Workspace model

Project folders are intentionally not hardcoded into shared Bash functions.

The `dev()` helper uses `$WORKSPACE`, which is defined per operating system:

- WSL: `wsl/env`
- Native Linux: `linux/env`

This keeps dotfiles portable while allowing each OS to store and build projects in the right native location.

## Safety notes

- Existing `.bashrc` and `.gitconfig` files should be backed up before linking.
- Secrets, tokens, `.env` files, and private keys do not belong in this repository.
- Run `dotlink --dry-run` before linking on a new machine.
- If you need a deeper view of the bootstrap contract, read [`docs/installer.md`](docs/installer.md).

## Current links

The main expected links are:

```text
~/.bashrc    -> ~/.dotfiles/bash/.bashrc
~/.zshrc     -> ~/.dotfiles/zsh/.zshrc
~/.gitconfig -> ~/.dotfiles/git/.gitconfig
~/.config/starship.toml -> ~/.dotfiles/config/.config/starship.toml
```
