# Project Source of Truth

These dotfiles provide configuration modules, declarative profiles, and symlink lifecycle for WSL and native Linux. The stable intent is to keep shell configuration, environment paths, Git configuration, and local tooling configuration understandable without turning this repository into a workstation provisioning system.

## Authority hierarchy

When docs disagree, use this order:

1. This document defines project purpose, boundaries, non-goals, and authority hierarchy.
2. `docs/dotfiles-contract.md` explains the local dotfiles contract and safety rules.
3. `docs/decisions/` records durable architecture decisions.
4. `docs/roadmap.md` tracks active or deferred work; it is not stable policy.
5. `README.md` is an entry map; it is never architecture authority.

## In scope

- Bash as the compatibility/base shell layer.
- Optional Zsh personalization without framework lock-in.
- Dotfile linking for repo-owned shell, Git, and XDG config files.
- Declarative profiles that select dotfiles modules without provisioning software.
- `bin/dotlink` lifecycle operations for link, list, status, unlink, and verify.

## Non-goals

- Managing secrets, tokens, private keys, or project `.env` files.
- Becoming a full OS configuration manager.
- Installing packages, tools, runtimes, Homebrew, or OS dependencies.
- Changing the default login shell automatically.
- Requiring a Go toolchain or TUI to set up a machine.
- Making README duplicate the dotlink contract or roadmap.
- Preserving compatibility for removed local installer or controller entrypoints.

## Navigation

| Need | Read |
|------|------|
| Dotfiles contract and safety rules | [`dotfiles-contract.md`](dotfiles-contract.md) |
| Active and deferred work | [`roadmap.md`](roadmap.md) |
| Durable architecture decisions | [`decisions/`](decisions/) |

Keep new docs focused on one job. If a change alters authority, update the links above and the README entry map in the same work unit.
