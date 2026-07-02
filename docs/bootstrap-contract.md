# Dotfiles Bootstrap Boundary

This repository is canonical only for dotfiles modules, declarative profiles, and symlink lifecycle. Shell-first bootstrap canonicality is superseded here: package installation, runtime installation, Homebrew setup, OS provisioning, and TUI bootstrap flows belong outside this repository.

## Contract surface

| Surface | Authority |
|---------|-----------|
| `bin/dotlink link` | Create repository-owned symlinks for selected modules or profiles. |
| `bin/dotlink list` | List modules selected by a profile or explicit arguments. |
| `bin/dotlink status` | Report missing, linked, drifted, or conflicting paths without modifying files. |
| `bin/dotlink unlink` | Remove only symlinks proven to be repository-owned. |
| `bin/dotlink verify` | Fail when selected links are missing, drifted, or conflicting. |

No local command in this repository installs software or bootstraps an operating system.

## Removed bootstrap surfaces

The following surfaces are intentionally removed or non-authoritative in this repository:

- `installer/install.sh` (removed; no compatibility shim)
- `installer/dotlink` (removed; no compatibility shim)
- `cmd/bootstrap-controller/` (removed; non-authoritative)
- `internal/controller/` (removed; non-authoritative)
- `bootstrap-controller` (removed; non-authoritative)
- controller-only Go module and tests

There is no compatibility shim and no preservation guarantee for the removed installer paths. Recover or migrate old bootstrap behavior from git history into a separate sibling bootstrapper if needed.

## Dotlink safety contract

- Dotlink manages only symlinks it can prove point into this repository.
- Regular files, directories, foreign symlinks, and unproven broken symlinks are conflicts.
- `status` and `verify` are read-only drift detectors.
- `unlink` removes only repository-owned symlinks.
- `link` rolls back only symlinks created during the failed operation.
- Profiles are restricted shell-data manifests, not executable provisioning scripts.

## External bootstrapper handoff

The sibling bootstrapper is external and docs-only in this repository. It may eventually own software installation, runtime installation, and machine provisioning. This repository must not implement that sibling bootstrapper beyond the handoff notes in [`bootstrapper-handoff.md`](bootstrapper-handoff.md).

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
- Use [`bootstrapper-handoff.md`](bootstrapper-handoff.md) for external bootstrapper boundaries.
- Use [`decisions/adr-0002-dotfiles-bootstrap-split.md`](decisions/adr-0002-dotfiles-bootstrap-split.md) for the durable split decision.
