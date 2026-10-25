# Dotfiles Contract

This repository is canonical only for dotfiles modules, declarative profiles, and symlink lifecycle. Package installation, runtime installation, Homebrew setup, OS provisioning, and Go/TUI controller behavior belong outside this repository.

## Contract surface

| Surface | Authority |
|---------|-----------|
| `bin/dotlink link` | Create repository-owned symlinks for selected modules or profiles. |
| `bin/dotlink list` | List modules selected by a profile or explicit arguments. |
| `bin/dotlink status` | Report missing, linked, drifted, skipped, or conflicting paths without modifying files. |
| `bin/dotlink unlink` | Remove only symlinks proven to be repository-owned. |
| `bin/dotlink verify` | Fail when selected links are missing, drifted, or conflicting. |

No local command in this repository installs software, configures operating-system dependencies, or provisions a workstation.

## Removed and non-authoritative surfaces

The following surfaces are intentionally removed or non-authoritative in this repository:

- `installer/install.sh` (removed; no compatibility shim)
- `installer/dotlink` (removed; no compatibility shim)
- `cmd/bootstrap-controller/` (removed; non-authoritative)
- `internal/controller/` (removed; non-authoritative)
- `bootstrap-controller` (removed; non-authoritative)
- controller-only Go module and tests

There is no compatibility shim and no preservation guarantee for the removed installer paths.

## Dotlink safety contract

- Dotlink manages only symlinks it can prove point into this repository.
- Regular files, directories, foreign symlinks, and unproven broken symlinks are conflicts.
- `status` and `verify` are read-only drift detectors.
- Optional modules that do not apply to the current platform are reported as `skip` and do
  not fail `verify`; a linked-but-broken optional module still reports drift or conflict.
- `unlink` removes only repository-owned symlinks.
- `link` rolls back only symlinks created during the failed operation.
- Profiles are restricted shell-data manifests, not executable provisioning scripts.
- Platform-specific Git settings live in a separate module and are reached through a
  Git `[include]`, never by making the common config machine-aware. The common
  `git/.gitconfig` stays portable: no machine paths, no absolute interpreter paths,
  and no Windows-only `core` keys.

## Fish: individual snippets

The `fish` module links only regular `*.fish` files directly inside
`fish/.config/fish/conf.d/` to `$XDG_CONFIG_HOME/fish/conf.d/`.
An empty or unset `XDG_CONFIG_HOME` falls back to `$DOTLINK_HOME/.config`
(`$HOME/.config` normally); a relative value is rejected. Before linking Fish,
`dotlink` checks every existing component from `/` through `fish/conf.d` and
rejects symbolic-link ancestors (including broken links) and non-directory
ancestors without modifying their destinations. `XDG_CONFIG_HOME` paths with
`.` or `..` components are rejected rather than normalized. Other modules retain
their existing destinations and directory-link behavior.

Select Fish explicitly with `bin/dotlink link fish`; existing profiles do not
select it. Fish is portable, not platform-optional: global `status` reports
missing snippets and global `verify` fails until they are linked, like other
non-optional modules. Existing files and foreign links remain conflicts.

`dotfiles.fish` initializes zoxide with `zoxide init fish | source` only when
its executable is available and the Fish function `__zoxide_z` is not already
defined. Without zoxide, the snippet leaves the shell unchanged. Reloading the
snippet or loading it after an existing zoxide initialization does not initialize
zoxide again when that function is present.

The duplicate-initialization guard relies on an internal function emitted by
zoxide 0.10.0, not a stable public API. Recheck it when upgrading zoxide. It does
not prevent a later snippet or `config.fish` from initializing zoxide again.

This module does not manage `config.fish`, prompts, distribution settings,
universal variables or history. Neighboring snippets remain untouched. Fish runs
snippets before `config.fish`; matching snippet names can shadow vendor files.
Do not reuse vendor names or source distribution configuration here.

Use the same XDG destination for link, status, verify and unlink. The existing
orphan scan covers `DOTLINK_HOME`, not external XDG trees: removing a source
snippet outside that tree may leave a broken link requiring manual inspection.

## Platform layers

The repository separates portable configuration from platform overrides without
branching inside dotlink, which is platform-agnostic by design.

| Layer | Path | Reached by |
|-------|------|------------|
| Portable Git config | `git/.gitconfig` | `base` and `interactive` profiles |
| Windows Git overrides | `git-win/.gitconfig.win` | Explicit `bin/dotlink link git-win` |

The common config includes `~/.gitconfig.win` through `[include]`. An absent include
is silently ignored by Git, so WSL and native Linux run on the portable values alone
and no profile has to select `git-win`.

## Recovery / Troubleshooting

When `status` or `verify` reports conflicts, drift, or missing links:

1. **Inspect the state** without modifying files:
   ```bash
   bin/dotlink status --profile base
   ```
2. **Identify the conflict type** for each reported path:
   - `conflict` — the path is a regular file, directory, foreign symlink, or broken symlink not owned by the repository.
   - `drift` — the path is a repository-owned symlink pointing at a different module or commit.
   - `missing` — the path does not exist.
3. **Resolve manually** before re-running `link`:
   - Back up the conflicting file or directory, then remove it.
   - For a foreign symlink that should not be managed, leave it in place and exclude the module from the profile.
   - For a drifted owned symlink, remove it and let `link` recreate it.
4. **Re-run link and verify**:
   ```bash
   bin/dotlink link --profile base
   bin/dotlink verify --profile base
   ```

If a previous `link` operation was interrupted, run `status` to see whether any partially-created symlinks remain; `unlink` removes only repository-owned symlinks.

## Related docs

- Use [`vision.md`](vision.md) for project boundaries.
- Use [`decisions/adr-0002-dotfiles-only-boundary.md`](decisions/adr-0002-dotfiles-only-boundary.md) for the durable ownership decision.
