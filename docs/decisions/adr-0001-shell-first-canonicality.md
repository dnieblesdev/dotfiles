# ADR 0001: Shell-first bootstrap canonicality

## Status

Superseded by [ADR 0002: Dotfiles/bootstrap split](adr-0002-dotfiles-bootstrap-split.md)

## Context

The repository includes a shell bootstrap and an optional Go controller/TUI path. Both surfaces expose bootstrap choices, but only the shell path owns the executable catalog, dependency expansion, plan/apply/list commands, privilege dispatch, controller handshake, and advisory state signing.

If the frontend were treated as an equal source of truth, documentation and behavior would drift: contributors would need to inspect both shell and Go code to understand what actually happens during bootstrap.

## Decision

This decision is superseded. `installer/install.sh`, `installer/dotlink`, `cmd/bootstrap-controller/`, and `internal/controller/` are removed or non-authoritative in this repository. Dotfiles authority is limited to configuration modules, declarative profiles, and symlink lifecycle.

## Consequences

- This ADR remains only as historical context for the previous bootstrap authority model.
- Current documentation must point readers to ADR 0002 and the dotfiles-only boundary.
- This repository does not preserve local compatibility for the removed installer or controller surfaces.
- Any future bootstrap canonicality decision belongs in a separate sibling bootstrapper boundary, not in this repository.
