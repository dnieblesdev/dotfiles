# Dotfiles

Personal dotfiles for a modular shell development environment across WSL and native Linux.

This README is an entry map. For project authority, use the focused docs below; if README conflicts with a deeper doc, the deeper doc wins.

## Start here

| Need | Read |
|------|------|
| Project purpose, boundaries, and non-goals | [`docs/vision.md`](docs/vision.md) |
| Shell-first bootstrap contract | [`docs/bootstrap-contract.md`](docs/bootstrap-contract.md) |
| Install commands and troubleshooting | [`docs/installer.md`](docs/installer.md) |
| Active and deferred work | [`docs/roadmap.md`](docs/roadmap.md) |
| Durable architecture decisions | [`docs/decisions/`](docs/decisions/) |

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

Launch the optional Go controller/TUI instead:

```bash
~/.dotfiles/installer/install.sh tui
```

The `tui` subcommand is opt-in. Running `install.sh` with no arguments remains the shell bootstrap. Details live in [`docs/installer.md`](docs/installer.md); the authority contract lives in [`docs/bootstrap-contract.md`](docs/bootstrap-contract.md).

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
| `installer/` | Shell-first installation and linking scripts |
| `docs/` | Project authority docs, operational guides, roadmap, and decisions |

## Common entry points

| Task | Entry point |
|------|-------------|
| Link repo modules into `$HOME` | `~/.dotfiles/installer/dotlink --dry-run bash git` |
| Run the shell bootstrap | `~/.dotfiles/installer/install.sh` |
| Inspect bootstrap actions | `~/.dotfiles/installer/install.sh list` |
| Understand bootstrap authority | [`docs/bootstrap-contract.md`](docs/bootstrap-contract.md) |

## Safety notes

- Existing `.bashrc` and `.gitconfig` files should be backed up before linking.
- Secrets, tokens, `.env` files, and private keys do not belong in this repository.
- Run `dotlink --dry-run` before linking on a new machine.
- For bootstrap authority, read [`docs/bootstrap-contract.md`](docs/bootstrap-contract.md).
