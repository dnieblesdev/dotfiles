# ADR 0002: Dotfiles-only boundary

## Status

Accepted

## Context

This repository had mixed dotfiles ownership with workstation setup responsibilities. That blurred ownership: configuration linking, package installation, runtime installation, controller handshakes, and Go/TUI frontend behavior all appeared locally authoritative.

## Decision

This repository is dotfiles-only. It owns configuration modules, declarative profile manifests, and symlink lifecycle through `bin/dotlink`. Local installer entrypoints and controller-only Go artifacts are removed without compatibility shims.

Removed or non-authoritative surfaces include `installer/install.sh`, `installer/dotlink`, `cmd/bootstrap-controller/`, `internal/controller/`, `bootstrap-controller`, and controller-only Go module artifacts.

## Consequences

- README and authority docs must describe dotfiles-only ownership first.
- Profiles must remain declarative shell data and must not provision software.
- `bin/dotlink` must refuse non-owned paths instead of overwriting them.
- Removed installer and controller behavior must not be reintroduced into this repository.
- Users expecting the removed installer paths must migrate; no local shim preserves those paths.
