# Project Source of Truth

These dotfiles provide configuration modules, declarative profiles, and symlink lifecycle for WSL and native Linux. The stable intent is to keep shell configuration, environment paths, Git configuration, and local tooling configuration understandable without turning this repository into a workstation bootstrapper.

## Authority hierarchy

When docs disagree, use this order:

1. This document defines project purpose, boundaries, non-goals, and authority hierarchy.
2. `docs/bootstrap-contract.md` explains the local dotfiles boundary and external bootstrapper handoff.
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
- Requiring a Go toolchain or TUI to bootstrap a machine.
- Making README duplicate the dotlink contract or roadmap.
- Preserving compatibility for removed local bootstrap entrypoints.

## Navigation

| Need | Read |
|------|------|
| Dotfiles/bootstrap boundary | [`bootstrap-contract.md`](bootstrap-contract.md) |
| External bootstrapper handoff | [`bootstrapper-handoff.md`](bootstrapper-handoff.md) |
| Active and deferred work | [`roadmap.md`](roadmap.md) |
| Durable architecture decisions | [`decisions/`](decisions/) |

Keep new docs focused on one job. If a change alters authority, update the links above and the README entry map in the same work unit.
