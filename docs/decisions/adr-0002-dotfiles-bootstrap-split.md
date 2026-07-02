# ADR 0002: Dotfiles/bootstrap split

## Status

Accepted

## Context

This repository had become both a dotfiles repository and a shell-first workstation bootstrapper. That blurred ownership: configuration linking, package installation, runtime installation, controller handshakes, and Go/TUI frontend behavior all appeared locally authoritative.

## Decision

This repository is dotfiles-only. It owns configuration modules, declarative profile manifests, and symlink lifecycle through `bin/dotlink`. Bootstrap behavior is split out: local installer entrypoints and controller-only Go artifacts are removed without compatibility shims.

Removed or non-authoritative surfaces include `installer/install.sh`, `installer/dotlink`, `cmd/bootstrap-controller/`, `internal/controller/`, `bootstrap-controller`, and controller-only Go module artifacts.

## Consequences

- README and authority docs must describe dotfiles-only ownership first.
- Profiles must remain declarative shell data and must not provision software.
- `bin/dotlink` must refuse non-owned paths instead of overwriting them.
- A future sibling bootstrapper may recover old bootstrap behavior from git history, but this repository must not implement it.
- Users expecting the removed installer paths must migrate; no local shim preserves those paths.
