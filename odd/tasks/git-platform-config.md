# Git platform config separation

Split `git/.gitconfig` into a portable common layer plus a conventional Windows namespace,
fix `core.symlinks`, and remove machine leakage. Issue #1.

## Specs

S1. `git/.gitconfig` MUST NOT contain machine-specific paths. `[safe] directory = /mnt/f/Vault/20_Desarrollo/20.10_Activos/charlybot` MUST be removed.

S2. `git/.gitconfig` MUST NOT hardcode an absolute interpreter path. The GitHub CLI credential helper MUST be `!gh auth git-credential`, resolved through `PATH`.

S3. `git/.gitconfig` MUST contain `core.autocrlf = input`. It MUST NOT contain `core.fscache` or `core.symlinks`.

S4. `git-win/.gitconfig.win` MUST contain the Windows-only overrides: `core.autocrlf = true`, `core.fscache = true`, `core.symlinks = false`.

S5. `git/.gitconfig` MUST include the Windows namespace via:
```
[include]
	path = ~/.gitconfig.win
```
When the file is absent the include MUST be silently ignored and git MUST keep working with the common values only.

S6. `dotlink` MUST accept `git-win` as a known module, and `dotlink link git-win` MUST create `~/.gitconfig.win -> <repo>/git-win/.gitconfig.win`.

S7. `dotlink status` with no arguments MUST still scan every known module, and `dotlink status --profile base` MUST NOT report `git-win`.

S8. Profiles `base` and `interactive` MUST remain unchanged: neither may select `git-win`.

S9. `filter.lfs.*` MUST stay in the common layer, unchanged (`clean`, `smudge`, `process`, `required = true`).

S10. `make all` MUST pass.

S11. Modules in `DOTLINK_OPTIONAL_MODULES` MUST be reported as `skip` by `status` and MUST NOT fail `verify` when absent. A linked-but-broken optional module MUST still report `drift` or `conflict` and fail normally.

## Tasks

| ID | Specs | Route | Commit |
|----|-------|-------|--------|
| T1 | S1, S2, S3 | Remove safe.directory, use PATH-resolved gh helper, keep autocrlf=input in common | 1 |
| T2 | S4 | Create `git-win/.gitconfig.win` with Windows overrides | 1 |
| T3 | S5 | Add `[include]` to common pointing at `~/.gitconfig.win` | 1 |
| T4 | S6 | Register `git-win` in `DOTLINK_KNOWN_MODULES` | 1 |
| T5 | S7, S8 | Regression test: status scan unchanged, profile base excludes git-win | 1 |
| T6 | S9 | Assert LFS filters unchanged in common | 1 |
| T7 | S5, S6 | Isolated test: `git config --show-origin` with and without the Windows file | 1 |
| T8 | S10 | Run `make all` and update docs (README module table, contract) | 1 |
| T9 | S11 | Optional-module skip semantics in dotlink + tests | 1 |

## Log

L1 (user original request, verbatim):
"si, miremos el roadmap y la issue."

Decision (user): issue #1 goes first, in the current layout (no `modules/` migration).
Decision (user): Windows layer uses the conventional namespace `git-win` -> `~/.gitconfig.win`.
Decision (user): remove the `safe.directory` entry.

Evidence: `docs/vision.md:3` declares "WSL and native Linux" as the supported environments.
Evidence: `~/.gitconfig.windows` is a valid git namespace; `~/.gitconfig.wsl` would be parsed as config for host `wsl`.
Evidence: `dotlink link <undeclared module>` prints "unknown module" and exits 1. An earlier
note claiming exit 0 was a measurement artifact (`$?` was reading `head` in a pipeline).
Verified with PIPESTATUS and a redirect: exit 1 for link/list/status/verify/unlink.
Evidence: a `[include]` of an absent file is silently ignored by git 2.53.0 and does not change exit status.
Evidence: `core.symlinks=false` converts tracked symlinks to regular files on clone under Linux.
Evidence: `filter.lfs.required` does not change the missing-executable failure; both values abort.
Evidence: `verify` with no args failed (exit 1) on Linux once `git-win` became a known module, confirming the platform-skip gap.
Decision (user): optional modules by platform in dotlink, rather than accepting a failing global verify.
