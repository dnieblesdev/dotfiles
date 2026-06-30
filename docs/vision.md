# Project Source of Truth

These dotfiles provide a shell-first, portable development environment for WSL and native Linux. The stable intent is to keep machine bootstrap, shell configuration, environment paths, Git configuration, and local tooling understandable without turning the repository into a general workstation manager.

## Authority hierarchy

When docs disagree, use this order:

1. `installer/install.sh` and `installer/lib/*.sh` define current executable bootstrap behavior.
2. `docs/bootstrap-contract.md` explains the stable shell bootstrap contract.
3. This document defines project purpose, boundaries, and non-goals.
4. `docs/installer.md` is operational usage and troubleshooting only.
5. `docs/roadmap.md` tracks active or deferred work; it is not stable policy.
6. `README.md` is an entry map; it is never architecture authority.

## In scope

- Bash as the compatibility/base shell layer.
- Optional Zsh personalization without framework lock-in.
- Dotfile linking for repo-owned shell, Git, and XDG config files.
- Shell-owned bootstrap for system packages, Homebrew tools, and runtime managers.
- Optional frontend surfaces that consume the shell contract without replacing it.

## Non-goals

- Managing secrets, tokens, private keys, or project `.env` files.
- Becoming a full OS configuration manager.
- Changing the default login shell automatically.
- Requiring a Go toolchain or TUI to bootstrap a machine.
- Making README duplicate the installer contract or roadmap.

## Navigation

| Need | Read |
|------|------|
| Bootstrap authority | [`bootstrap-contract.md`](bootstrap-contract.md) |
| Install commands | [`installer.md`](installer.md) |
| Active and deferred work | [`roadmap.md`](roadmap.md) |
| Durable architecture decisions | [`decisions/`](decisions/) |

Keep new docs focused on one job. If a change alters authority, update the links above and the README entry map in the same work unit.
