# Dotfiles — Agent Operating Guide

This repository owns **dotfiles modules, declarative profiles, and symlink lifecycle only**. It links repo-owned configuration into `$HOME`. It does **not** install packages, runtimes, tools, Homebrew, or OS dependencies.

## Project identity

Use `dotfiles` as the project name for Engram searches, saves, and SDD artifact lookup. The repository directory is named `.dotfiles`, but that is **not** the Engram project identifier.

If you are an agent arriving from another repository, this file is your entry point. It tells you what is safe to call and what is intentionally gone.

## What this repository is and is not

| Is (use it) | Is not (do not look for it here) |
|-------------|----------------------------------|
| Shell, Git, and XDG config modules | Package / runtime / OS installation |
| Declarative profile manifests | Workstation provisioning |
| Symlink lifecycle via `bin/dotlink` | A Go toolchain or TUI controller flow |
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
make verify   # dotfiles boundary drift verifier
make all      # check + test + verify
```

## CodeGraph warning

Do **not** treat CodeGraph as authoritative for this repository.

This repo is mostly shell fragments, extensionless dotfiles, Markdown, TOML,
and Git config. CodeGraph v1.1.3 currently reports `No files found to index`
for this tree and may show a healthy daemon with an empty index:

```
Files: 0
Nodes: 0
Edges: 0
```

If CodeGraph returns no results here, that is expected tooling coverage, not
proof that the repository is empty or that symbols do not exist. Prefer direct
file inspection, `git ls-files`, and the documented quality gates above for
this repo.

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

Old installer and controller behavior was removed from this repository. Do not recreate it here.

## Authority chain (when documents disagree)

Read in this order. Earlier wins over later.

1. `docs/vision.md` — project purpose, boundaries, non-goals, authority hierarchy
2. `docs/dotfiles-contract.md` — dotfiles contract surface and safety rules
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
| Dotfiles contract and recovery runbook | [`docs/dotfiles-contract.md`](docs/dotfiles-contract.md) |
| Durable architecture decisions | [`docs/decisions/`](docs/decisions/) |
| Active and deferred work | [`docs/roadmap.md`](docs/roadmap.md) |

## Quick path for an external agent

1. `~/.dotfiles/bin/dotlink status --profile base` — inspect current link state (read-only).
2. `~/.dotfiles/bin/dotlink link --profile base` — link base modules if status is clean.
3. `~/.dotfiles/bin/dotlink verify --profile base` — confirm links are correct.
4. If you need software installed — stop; that is not this repository's job.
