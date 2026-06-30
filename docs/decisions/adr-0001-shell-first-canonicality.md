# ADR 0001: Shell-first bootstrap canonicality

## Status

Accepted

## Context

The repository includes a shell bootstrap and an optional Go controller/TUI path. Both surfaces expose bootstrap choices, but only the shell path owns the executable catalog, dependency expansion, plan/apply/list commands, privilege dispatch, controller handshake, and advisory state signing.

If the frontend were treated as an equal source of truth, documentation and behavior would drift: contributors would need to inspect both shell and Go code to understand what actually happens during bootstrap.

## Decision

`installer/install.sh` and `installer/lib/*.sh` are the canonical bootstrap implementation. Go/TUI code is an optional frontend that consumes the shell contract and must fall back to shell behavior when the contract is unavailable or incompatible.

## Consequences

- Bootstrap documentation must describe shell-owned behavior first.
- README must link to authority docs instead of duplicating the contract.
- Frontend changes must preserve shell contract compatibility.
- Any conflict between shell behavior and frontend docs is resolved in favor of the shell behavior.
