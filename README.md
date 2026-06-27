# Dotfiles

Personal dotfiles for a modular Bash-based development environment across WSL and native Linux.

This repository keeps shell configuration, environment paths, Git configuration, and bootstrap scripts organized by responsibility instead of keeping everything in one large `.bashrc`.

## Quick install

Clone the repository:

```bash
git clone https://github.com/dnieblesdev/dotfiles.git ~/.dotfiles
```

Link the active dotfiles:

```bash
~/.dotfiles/bootstrap/dotlink bash git
```

Or run the full bootstrap:

```bash
~/.dotfiles/bootstrap/install.sh
```

## Structure

| Path | Purpose |
|------|---------|
| `bash/` | Main Bash entrypoint, aliases, prompt, completions, shell config, and functions |
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
~/.gitconfig -> ~/.dotfiles/git/.gitconfig
```
