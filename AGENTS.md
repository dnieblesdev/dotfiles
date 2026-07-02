# Dotfiles — Agent Operating Guide

This repository owns **dotfiles modules, declarative profiles, and symlink lifecycle only**. It links repo-owned configuration into `$HOME`. It does **not** install packages, runtimes, tools, Homebrew, or OS dependencies — that belongs in an external sibling bootstrapper.

If you are an agent arriving from another repository (e.g. a bootstrapper), this file is your entry point. It tells you what is safe to call and what is intentionally gone.

## What this repository is and is not

| Is (use it) | Is not (do not look for it here) |
|-------------|----------------------------------|
| Shell, Git, and XDG config modules | Package / runtime / OS installation |
| Declarative profile manifests | Workstation bootstrap or provisioning |
| Symlink lifecycle via `bin/dotlink` | A Go toolchain or TUI bootstrap flow |
| Drift detection and verification | Secret / token / `.env` management |

## Entrypoints (the only executable surface)

`bin/dotlink` is the single visible entrypoint. There is nothing else to invoke.

```
bin/dotlink link   [--profile NAME] | MODULE...
bin/dotlink list   [--profile NAME]
bin/dotlink status [--profile NAME] | MODULE...
bin/dotlink unlink [--profile NAME] | MODULE...
bin/dotlink verify [--profile NAME] | MODULE...
```

Rules you must respect:

- `--profile NAME` and explicit `MODULE...` arguments are **mutually exclusive**. Never combine them.
- `status` and `verify` with **no arguments** scan ALL known modules, not just `base`.
- `unlink` removes **only** symlinks it can prove point into this repository. It will not touch foreign files.
- `link` rolls back only the symlinks created during a failed operation.

Profiles available:

| Profile | Modules | Purpose |
|---------|---------|---------|
| `base` | `bash git` | Base shell and Git dotfiles |
| `interactive` | `bash git zsh config` | Interactive shell and terminal config |

Note: `env/` is sourced by `.bashrc` and is **not** managed by dotlink (it contains non-hidden files).

Quality gate (run before trusting changes):

```
make check    # bash -n syntax check across scripts
make test     # dotlink integration/regression tests
make verify   # bootstrap-split drift verifier
make all      # check + test + verify
```

## Do not use — removed or non-authoritative

These surfaces were intentionally removed. There is **no compatibility shim and no preservation guarantee**. Do not call them, recreate them here, or depend on them.

| Removed surface | Status |
|-----------------|--------|
| `installer/install.sh` | Removed, no shim |
| `installer/dotlink` | Removed, no shim |
| `cmd/bootstrap-controller/` | Removed, non-authoritative |
| `internal/controller/` | Removed, non-authoritative |
| `bootstrap-controller` binary | Removed, non-authoritative |
| `go.mod` and Go module | Removed |

To recover old bootstrap behavior: pull it from git history into a **separate sibling bootstrapper repository**, never back into this one.

## Authority chain (when documents disagree)

Read in this order. Earlier wins over later.

1. `docs/vision.md` — project purpose, boundaries, non-goals, authority hierarchy
2. `docs/bootstrap-contract.md` — dotfiles/bootstrap boundary, contract surface, safety rules
3. `docs/decisions/` — durable architecture decisions (ADRs)
4. `docs/roadmap.md` — active/deferred work (not stable policy)
5. `README.md` — entry map only, never architecture authority
6. This file — agent entry map, points at the above; never overrides them

## Safety contract (do not violate)

- Dotlink manages only symlinks it can prove point into this repository.
- Regular files, directories, foreign symlinks, and unproven broken symlinks are **conflicts** — they block linking and must be resolved manually.
- Existing `.bashrc` and `.gitconfig` block linking and must be moved manually before dotlink will manage them.
- `status` and `verify` are read-only; they never modify files.
- Secrets, tokens, `.env` files, and private keys do not belong in this repository.
- Profiles are restricted shell-data manifests, **not** executable provisioning scripts. Never add executable provisioning logic to a profile.

## Deeper context

| Need | Read |
|------|------|
| Project purpose and boundaries | [`docs/vision.md`](docs/vision.md) |
| Dotfiles/bootstrap boundary and recovery runbook | [`docs/bootstrap-contract.md`](docs/bootstrap-contract.md) |
| External bootstrapper handoff | [`docs/bootstrapper-handoff.md`](docs/bootstrapper-handoff.md) |
| Durable architecture decisions | [`docs/decisions/`](docs/decisions/) |
| Active and deferred work | [`docs/roadmap.md`](docs/roadmap.md) |

## Quick path for an external agent

1. `~/.dotfiles/bin/dotlink status --profile base` — inspect current link state (read-only).
2. `~/.dotfiles/bin/dotlink link --profile base` — link base modules if status is clean.
3. `~/.dotfiles/bin/dotlink verify --profile base` — confirm links are correct.
4. If you need software installed — stop; that is not this repository's job.
