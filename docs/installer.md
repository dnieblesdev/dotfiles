# Bootstrap status

This repository now has a shell-first bootstrap that can restore a machine from zero, re-run selectively, and keep a deterministic plan/state flow under `$XDG_STATE_HOME`.

## Quick path

1. Clone the repo.
2. Run `~/.dotfiles/installer/install.sh`.
3. Use `plan`, `list`, or `apply` to re-run selected actions later.
4. Link optional shell layers with `dotlink` when needed.
5. Launch the optional Go controller with `~/.dotfiles/installer/install.sh tui` (reuses the user-local Go runtime if needed).

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
| Go runtime | Normal `apply` installs or exposes user-local Go when `go` is not already on `PATH`. |
| Optional Go UI | `bootstrap-controller` is a thin frontend only; shell remains the source of truth. |

## Known debt

The bootstrap is usable, but the following hardening items remain intentionally deferred:

- replay/state provenance still deserves a dedicated follow-up review
- optional Go controller falls back to shell when the handshake is missing or outdated

Completed in this slice:

- explicit confirmation now gates sudo-mediated privileged dispatch
- privileged child launches use a trusted fixed PATH allowlist
- normal `apply` now includes `runtime-go`; `tui` reuses the same Go helper

## Checklist

- [x] Shell bootstrap exists
- [x] Selective rerun support exists
- [x] Advisory state is isolated from the repo
- [x] Dev tools are split from system packages
- [x] Final privilege hardening pass

## Next step

Harden the `tui` launcher for offline Go installation and signed bootstrap-controller builds.

## Go runtime and optional controller path

The default shell bootstrap includes `runtime-go`. If `go` is already on `PATH`, it is a no-op. Otherwise it installs Go user-locally at `~/.local/go`, symlinks `go` and `gofmt` into `~/.local/bin`, and the shared shell environment loads `env/go` for future shells.

The Go controller remains opt-in and is launched by the shell with the `tui` subcommand.

```bash
bash installer/install.sh                     # includes runtime-go during normal apply
bash installer/install.sh tui                 # reuses Go and exec's the controller
bash installer/install.sh tui --only brew-tools  # forwards --only to bootstrap-controller
bash installer/install.sh tui --help          # shows the controller's flag usage
```

The launcher:

1. Detects Go via `command -v go`. If missing, it reuses the user-local runtime helper. No sudo, no system package manager.
2. Builds `bootstrap-controller` from `cmd/bootstrap-controller/` into `~/.local/bin/bootstrap-controller` if the binary is missing or older than its sources. The build is skipped when the binary is already up-to-date.
3. `exec`s `bootstrap-controller`, forwarding every arg after `tui`. The controller then handshakes with `installer/install.sh controller`, reads the shell-owned catalog via `installer/install.sh list --format json`, and finally calls `installer/install.sh apply`.

Default Go version is `1.23.4`. Override with `BOOTSTRAP_TUI_GO_VERSION` before the first Go runtime install. The default `install.sh` (no args or `apply`) remains the shell source of truth; `tui` is only the optional controller frontend.

Building or testing the optional Go controller locally still requires Go 1.23+ when developing it directly. End users do not need a pre-existing Go toolchain.
