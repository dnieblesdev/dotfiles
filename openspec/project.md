# Project Context: dotfiles

## Purpose

This repository owns dotfiles modules, declarative profile manifests, and the lifecycle of symlinks into the user's home directory. `bin/dotlink` is the only executable entrypoint.

## Boundaries

- In scope: shell, Git, XDG configuration modules; declarative profile selection; safe link, list, status, unlink, and verify behavior.
- Out of scope: package or runtime installation, Homebrew, OS provisioning, bootstrap/controller flows, installer compatibility shims, secrets, tokens, and `.env` management.
- Profile `.sh` files are restricted shell-data manifests, not provisioning scripts.
- Preserve the safety rule that dotlink manages only symlinks proven to point into this repository.

## Authority

Follow this order when sources disagree: `docs/vision.md`, `docs/dotfiles-contract.md`, `docs/decisions/`, `docs/roadmap.md`, `README.md`, then `AGENTS.md` as the agent entry map. Existing active specs under `openspec/specs/` capture the current SDD contract.

## Quality gates

- `make check` — shell syntax checks
- `make test` — dotlink integration/regression tests
- `make verify` — repository boundary verification
- `make all` — all gates

## Initialization notes

This context bootstrap is planning-only. It does not change dotlink code, tests, documentation, or behavior.
