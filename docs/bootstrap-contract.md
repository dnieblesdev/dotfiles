# Bootstrap Contract

The shell bootstrap is canonical. `installer/install.sh` and `installer/lib/*.sh` own the catalog, planning, apply flow, list output, privilege model, advisory state, and controller handshake. Go and TUI code may make that flow easier to use, but they are optional frontends.

## Contract surface

| Surface | Authority |
|---------|-----------|
| `installer/install.sh apply` | Default bootstrap execution path. |
| `installer/install.sh plan` | Deterministic plan computation for selected actions. |
| `installer/install.sh list` | Catalog and advisory status inspection. |
| `installer/install.sh controller` | Handshake endpoint for optional Go frontend integration. |
| `installer/install.sh tui` | Launcher for the optional Go controller/TUI. |

Running `installer/install.sh` without a command defaults to `apply`.

## Catalog and planning

The catalog lives in `installer/lib/catalog.sh`. It defines ordered actions, labels, groups, dependencies, and privilege metadata. Current action groups are:

- `system`: distro system packages.
- `brew`: Homebrew bootstrap and brew-managed developer tools.
- `dotfiles`: clone, backup, and link steps.
- `runtime`: Go, nvm, uv, and rustup runtime managers.

The planner expands dependencies, validates known actions, computes selected work from `--only`, `--skip`, and `--force`, and can emit text or JSON. Saved plans are checked against the current catalog hash and execution context before replay.

## Privileges

Privilege is per action. System package installation is the elevated phase; Homebrew tools, dotfile operations, and runtime managers are user-owned by design. If elevation is needed, the shell flow asks for explicit confirmation and runs children with a trusted fixed PATH.

## Advisory state

Bootstrap state is advisory and lives under `${XDG_STATE_HOME:-$HOME/.local/state}/dniebles` unless overridden by bootstrap state environment variables. The state file records catalog hash, execution context, status, selected actions, and completed actions. State and saved plans are signed with a local HMAC secret so stale or tampered replay is rejected.

## Optional Go/TUI frontend

The Go controller is a thin adapter:

1. It handshakes with `installer/install.sh controller`.
2. It loads choices through `installer/install.sh list --format json`.
3. It applies selected actions through `installer/install.sh apply`.
4. If the handshake or payload is unsupported, it falls back to the shell bootstrap.

The frontend must not invent catalog behavior, privilege rules, or state semantics. If frontend behavior and shell behavior diverge, the shell contract wins.

## Related docs

- Use [`installer.md`](installer.md) for commands and troubleshooting.
- Use [`vision.md`](vision.md) for project boundaries.
- Use [`decisions/adr-0001-shell-first-canonicality.md`](decisions/adr-0001-shell-first-canonicality.md) for the durable shell-first decision.
