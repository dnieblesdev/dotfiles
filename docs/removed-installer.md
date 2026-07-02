# Removed installer guide

This guide is non-authoritative. The local installer has been removed from this repository; dotfiles authority now lives in [`vision.md`](vision.md), [`bootstrap-contract.md`](bootstrap-contract.md), and `bin/dotlink`.

## Quick path

1. Clone the repo.
2. Run `~/.dotfiles/bin/dotlink link --profile base` to link base dotfiles.
3. Run `~/.dotfiles/bin/dotlink status --profile base` to inspect links without modifying files.
4. Use a future external sibling bootstrapper for package, runtime, or OS provisioning.

## Details

| Task | Command |
|------|---------|
| Link base dotfiles | `~/.dotfiles/bin/dotlink link --profile base` |
| Link interactive dotfiles | `~/.dotfiles/bin/dotlink link --profile interactive` |
| List selected modules | `~/.dotfiles/bin/dotlink list --profile base` |
| Inspect link state | `~/.dotfiles/bin/dotlink status --profile base` |
| Verify links | `~/.dotfiles/bin/dotlink verify --profile base` |
| Remove repo-owned links | `~/.dotfiles/bin/dotlink unlink --profile base` |

For the removed bootstrap boundary and no-shim decision, use [`bootstrap-contract.md`](bootstrap-contract.md).

## Troubleshooting notes

Known deferred hardening work is tracked in [`roadmap.md`](roadmap.md). Operationally, remember:

- Dotlink does not change your default shell automatically.
- Dotlink refuses regular files and foreign symlinks instead of overwriting them.
- Homebrew, runtime managers, and OS packages are outside this repository.
- Removed bootstrap implementation can be recovered from git history for migration into a sibling project.

## Checklist

- [x] Local installer marked removed and non-authoritative
- [x] Dotlink is the visible local lifecycle command
- [x] External bootstrapper remains docs-only

## Next step

Use [`bootstrapper-handoff.md`](bootstrapper-handoff.md) for the external bootstrapper boundary. Do not treat this guide as policy authority.
