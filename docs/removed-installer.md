# Removed installer guide

This guide is non-authoritative. The local installer has been removed from this repository; dotfiles authority now lives in [`vision.md`](vision.md), [`dotfiles-contract.md`](dotfiles-contract.md), and `bin/dotlink`.

## Quick path

1. Clone the repo.
2. Run `~/.dotfiles/bin/dotlink link --profile base` to link base dotfiles.
3. Run `~/.dotfiles/bin/dotlink status --profile base` to inspect links without modifying files.
4. Use tooling outside this repository for package, runtime, or OS provisioning.

## Details

| Task | Command |
|------|---------|
| Link base dotfiles | `~/.dotfiles/bin/dotlink link --profile base` |
| Link interactive dotfiles | `~/.dotfiles/bin/dotlink link --profile interactive` |
| List selected modules | `~/.dotfiles/bin/dotlink list --profile base` |
| Inspect link state | `~/.dotfiles/bin/dotlink status --profile base` |
| Verify links | `~/.dotfiles/bin/dotlink verify --profile base` |
| Remove repo-owned links | `~/.dotfiles/bin/dotlink unlink --profile base` |

For removed entrypoints and the no-shim decision, use [`dotfiles-contract.md`](dotfiles-contract.md).

## Troubleshooting notes

Known deferred hardening work is tracked in [`roadmap.md`](roadmap.md). Operationally, remember:

- Dotlink does not change your default shell automatically.
- Dotlink refuses regular files and foreign symlinks instead of overwriting them.
- Homebrew, runtime managers, and OS packages are outside this repository.
- Removed installer and controller behavior is historical and must not be restored here.

## Checklist

- [x] Local installer marked removed and non-authoritative
- [x] Dotlink is the visible local lifecycle command
- [x] Package, runtime, and OS provisioning remain out of scope

## Next step

Use [`dotfiles-contract.md`](dotfiles-contract.md) for the dotfiles contract. Do not treat this guide as policy authority.
