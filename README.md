# Dotfiles

Personal dotfiles for a modular shell development environment across WSL and native Linux.

This repository keeps shell configuration, environment paths, Git configuration, and bootstrap scripts organized by responsibility instead of keeping everything in one large shell file.

Bash remains the compatibility/base layer. Zsh is an optional interactive personalization layer with lightweight tools and no Oh My Zsh dependency.

## Quick install

Clone the repository:

```bash
git clone https://github.com/dnieblesdev/dotfiles.git ~/.dotfiles
```

Link the active dotfiles:

```bash
~/.dotfiles/bootstrap/dotlink bash git
```

Link the optional Zsh interactive layer and Starship config:

```bash
~/.dotfiles/bootstrap/dotlink zsh config
```

Or run the full bootstrap:

```bash
~/.dotfiles/bootstrap/install.sh
```

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
| `bootstrap/` | Installation and linking scripts |

## dotlink

`dotlink` is a small local linker inspired by GNU Stow, but intentionally limited to this repository's needs.

It links dotfiles from module folders into `$HOME`:

```bash
~/.dotfiles/bootstrap/dotlink bash git
```

Useful commands:

```bash
~/.dotfiles/bootstrap/dotlink --list
~/.dotfiles/bootstrap/dotlink --dry-run bash git
~/.dotfiles/bootstrap/dotlink --delete bash
```

`dotlink` also supports nested dot directories such as `.config/`, so `config/.config/starship.toml` links to `~/.config/starship.toml`.

## Zsh interactive layer

The Zsh layer is intentionally small and transparent. It does not use Oh My Zsh.

It expects or installs these tools when available:

- `zsh`
- `starship`
- `zoxide`
- `fzf`
- `bat` / `batcat`
- `eza`
- `ripgrep`
- `fd` / `fdfind`
- `tldr` or `tealdeer`

Install and link everything with the bootstrap:

```bash
~/.dotfiles/bootstrap/install.sh
```

Or link only the Zsh layer after cloning:

```bash
~/.dotfiles/bootstrap/dotlink zsh config
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

## Current links

The main expected links are:

```text
~/.bashrc    -> ~/.dotfiles/bash/.bashrc
~/.zshrc     -> ~/.dotfiles/zsh/.zshrc
~/.gitconfig -> ~/.dotfiles/git/.gitconfig
~/.config/starship.toml -> ~/.dotfiles/config/.config/starship.toml
```
