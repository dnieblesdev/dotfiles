# Installer guide

This guide is operational: commands, expected usage, and troubleshooting. For authority and design boundaries, read [`bootstrap-contract.md`](bootstrap-contract.md).

## Quick path

1. Clone the repo.
2. Run `~/.dotfiles/installer/install.sh`.
3. Use `plan`, `list`, or `apply` to re-run selected actions later.
4. Link optional shell layers with `dotlink` when needed.
5. Launch the optional Go controller with `~/.dotfiles/installer/install.sh tui` only when you want the frontend path.

## Details

| Task | Command |
|------|---------|
| Default bootstrap | `~/.dotfiles/installer/install.sh` |
| Preview plan | `~/.dotfiles/installer/install.sh plan` |
| List actions and status | `~/.dotfiles/installer/install.sh list` |
| Run selected actions | `~/.dotfiles/installer/install.sh apply --only ACTION[,ACTION...]` |
| Skip selected actions | `~/.dotfiles/installer/install.sh apply --skip ACTION[,ACTION...]` |
| Launch optional frontend | `~/.dotfiles/installer/install.sh tui` |

For action groups, privilege boundaries, state signing, and frontend authority, use [`bootstrap-contract.md`](bootstrap-contract.md).

## Troubleshooting notes

Known deferred hardening work is tracked in [`roadmap.md`](roadmap.md). Operationally, remember:

- The bootstrap does not change your default shell automatically.
- If linked files look wrong, run `dotlink --list` or `dotlink --dry-run`.
- If Homebrew is unavailable, brew-managed tools may be skipped while other phases continue.
- The optional Go controller falls back to the shell path when its handshake is unavailable or incompatible.

## Checklist

- [x] Shell bootstrap exists
- [x] Selective rerun support exists
- [x] Advisory state is isolated from the repo
- [x] Dev tools are split from system packages
- [x] Final privilege hardening pass

## Next step

Use [`roadmap.md`](roadmap.md) for active/deferred work. Do not treat this guide as policy authority.

## Go runtime and optional controller path

The default shell bootstrap includes `runtime-go`. If `go` is already on `PATH`, it is a no-op. Otherwise it installs Go user-locally at `~/.local/go`, symlinks `go` and `gofmt` into `~/.local/bin`, and the shared shell environment loads `env/go` for future shells.

The Go controller remains opt-in and is launched by the shell with the `tui` subcommand.

```bash
bash installer/install.sh                     # includes runtime-go during normal apply
bash installer/install.sh tui                 # reuses Go and exec's the controller
bash installer/install.sh tui --only brew-tools  # forwards --only to bootstrap-controller
bash installer/install.sh tui --help          # shows the controller's flag usage
```

The launcher operational path:

1. Detects Go via `command -v go`. If missing, it reuses the user-local runtime helper. No sudo, no system package manager.
2. Builds `bootstrap-controller` from `cmd/bootstrap-controller/` into `~/.local/bin/bootstrap-controller` if the binary is missing or older than its sources. The build is skipped when the binary is already up-to-date.
3. `exec`s `bootstrap-controller`, forwarding every arg after `tui`. The controller then handshakes with `installer/install.sh controller`, reads the shell-owned catalog via `installer/install.sh list --format json`, and finally calls `installer/install.sh apply`.

Default Go version is `1.23.4`. Override with `BOOTSTRAP_TUI_GO_VERSION` before the first Go runtime install. The default `install.sh` (no args or `apply`) remains the shell path; `tui` is only the optional controller frontend.

Building or testing the optional Go controller locally still requires Go 1.23+ when developing it directly. End users do not need a pre-existing Go toolchain.
