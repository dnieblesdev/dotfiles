# Bootstrap status

This repository now has a shell-first bootstrap that can restore a machine from zero, re-run selectively, and keep a deterministic plan/state flow under `$XDG_STATE_HOME`.

## Quick path

1. Clone the repo.
2. Run `~/.dotfiles/installer/install.sh`.
3. Use `plan`, `list`, or `apply` to re-run selected actions later.
4. Link optional shell layers with `dotlink` when needed.

## Details

| Area | Decision |
|------|----------|
| Shell core | Bash remains the canonical fallback and source of truth. |
| Optional UI | A future Go frontend is optional and must consume the same shell contract. |
| System tools | Install through the distro package manager (`apt` or `pacman`). |
| Dev tools | Install through Homebrew when available. |
| Runtimes | Keep separate (`rustup`, `uv`, and the chosen Node manager path). |
| Privileges | Resolve per action; only elevate when the action truly needs it. |
| Plan/state | Advisory state lives under `$XDG_STATE_HOME` and is tamper-evident. |
| Optional Go | `bootstrap-controller` is a thin frontend only; shell remains the source of truth. |

## Known debt

The bootstrap is usable, but the following hardening items remain intentionally deferred:

- replay/state provenance still deserves a dedicated follow-up review
- optional Go controller falls back to shell when the handshake is missing or outdated

Completed in this slice:

- explicit confirmation now gates sudo-mediated privileged dispatch
- privileged child launches use a trusted fixed PATH allowlist

## Checklist

- [x] Shell bootstrap exists
- [x] Selective rerun support exists
- [x] Advisory state is isolated from the repo
- [x] Dev tools are split from system packages
- [x] Final privilege hardening pass

## Next step

Optional Go frontend slice: a thin TUI/controller that only selects actions and emits the existing shell contract.

## Optional Go path

The Go controller is opt-in. It first handshakes with `installer/install.sh controller`, then reads the shell-owned catalog via `installer/install.sh list --format json`, and finally calls `installer/install.sh apply`.

If the Go binary is missing, outdated, or the shell handshake fails, the flow falls back to the shell bootstrap directly.

Building or testing the optional Go controller locally requires Go 1.23+.
