# Dotfiles

Personal dotfiles for a modular shell development environment across WSL and native Linux.

This README is an entry map for dotfiles only. This repository owns configuration modules, declarative profiles, and symlink lifecycle; it does not own workstation bootstrap, package installation, runtime installation, or OS provisioning.

## Start here

| Need | Read |
|------|------|
| Project purpose, boundaries, and non-goals | [`docs/vision.md`](docs/vision.md) |
| Dotfiles/bootstrap authority boundary | [`docs/bootstrap-contract.md`](docs/bootstrap-contract.md) |
| External bootstrapper handoff | [`docs/bootstrapper-handoff.md`](docs/bootstrapper-handoff.md) |
| Active and deferred work | [`docs/roadmap.md`](docs/roadmap.md) |
| Durable architecture decisions | [`docs/decisions/`](docs/decisions/) |

## Quick path

Clone the repository:

```bash
git clone https://github.com/dnieblesdev/dotfiles.git ~/.dotfiles
```

Link the base dotfiles profile:

```bash
~/.dotfiles/bin/dotlink link --profile base
```

Link the optional interactive profile:

```bash
~/.dotfiles/bin/dotlink link --profile interactive
```

Inspect status without modifying files:

```bash
~/.dotfiles/bin/dotlink status --profile base
```

Verify existing links:

```bash
~/.dotfiles/bin/dotlink verify --profile base
```

There is no local bootstrap command in this repository. A future sibling bootstrapper may install software and runtimes externally; this repository only links dotfiles.

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
| `profiles/` | Declarative dotfiles profile manifests |
| `bin/dotlink` | Visible dotfiles linker entrypoint |
| `dotlink/` | Dotlink implementation, safety checks, and tests |
| `docs/` | Project authority docs, operational guides, roadmap, and decisions |

## Common entry points

| Task | Entry point |
|------|-------------|
| Link repo modules into `$HOME` | `~/.dotfiles/bin/dotlink link --profile base` |
| Inspect dotfile link state | `~/.dotfiles/bin/dotlink status --profile base` |
| Remove repo-owned links | `~/.dotfiles/bin/dotlink unlink --profile base` |
| Understand bootstrap boundary | [`docs/bootstrap-contract.md`](docs/bootstrap-contract.md) |

## Safety notes

- Existing `.bashrc` and `.gitconfig` files block linking and must be moved manually before dotlink will manage them.
- Secrets, tokens, `.env` files, and private keys do not belong in this repository.
- `bin/dotlink` refuses regular files, foreign symlinks, and broken symlinks it cannot prove are repository-owned.
- For the bootstrap boundary, read [`docs/bootstrap-contract.md`](docs/bootstrap-contract.md).
