# Proposal: Split Dotfiles Bootstrap Identity

## Intent

Restore this repository as `dotfiles`, not a tool/runtime bootstrapper. Installing runtimes/packages changed the repo identity, and Bash cannot remain the long-term bootstrap core. This repo becomes authoritative only for configuration modules, declarative profiles, and symlink lifecycle.

## Scope

### In Scope
- Update README, source-of-truth docs, ADRs, and bootstrap docs to supersede shell-first bootstrap authority here.
- Define the dotfiles repo boundary: modules, profiles, dotlink behavior, and symlink lifecycle.
- Add visible `bin/dotlink` backed by a dedicated implementation area.
- Introduce declarative dotfiles profile manifests from the start.
- Add docs-only sibling bootstrapper scaffold/handoff if feasible.
- Remove bootstrap authority, both legacy installer entrypoints (`installer/install.sh`, `installer/dotlink`), and Go bootstrap-controller/controller-only Go artifacts without shims.

### Out of Scope
- Full sibling bootstrapper implementation.
- Migrating all bootstrap code in this pass.
- Installing tools, packages, or runtimes.
- Preserving compatibility for either legacy installer entrypoint (`installer/install.sh`, `installer/dotlink`).
- Keeping `cmd/bootstrap-controller/`, `internal/controller/`, or controller-only Go artifacts authoritative in this repository.

## Capabilities

### New Capabilities
- `dotlink-lifecycle`: visible entrypoint, implementation boundary, and link/list/status/unlink/verify semantics.
- `profile-manifests`: declarative profiles selecting modules without package/runtime installation.

### Modified Capabilities
- `project-source-of-truth`: replace shell-first bootstrap canonicality with dotfiles-only authority and sibling-bootstrapper handoff rules.

## Approach

Split authority immediately. This repo supersedes old shell-first canonicality for its boundary and keeps bootstrap canonicality only as future sibling-project context. Docs lead; implementation movement is limited to making dotlink/profile direction visible and removing misleading bootstrap authority.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `README.md` | Modified | Dotfiles entry map, not bootstrap launcher. |
| `docs/vision.md` | Modified | Dotfiles-only source of truth. |
| `docs/bootstrap-contract.md`, `docs/installer.md` | Modified/Removed | Mark non-authoritative or migrate. |
| `docs/decisions/` | Modified/New | ADR superseding shell-first authority for this repo. |
| `installer/install.sh`, `installer/dotlink` | Removed | Old installer entrypoints break intentionally; no shim or fallback remains authoritative. |
| `cmd/bootstrap-controller/`, `internal/controller/`, controller-only Go artifacts | Removed | Go bootstrap-controller code is no longer authoritative in this repo. |
| `bin/dotlink`, dotlink implementation area | New/Modified | Visible core dotfiles entrypoint. |
| profile manifest paths | New | Declarative module/profile selection. |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Broken bootstrap expectations | High | State incompatibility explicitly and update entry docs. |
| Duplicate authority docs | Med | Add ADR/source-of-truth links and mark stale docs non-authoritative. |
| Overbuilding bootstrapper scaffold | Med | Keep sibling project docs-only in this pass. |

## Rollback Plan

Revert the change folder and repo edits in one commit. Restore previous README/bootstrap docs and installer entrypoints from git if downstream use breaks.

## Dependencies

- Existing `project-source-of-truth` spec.
- User acceptance that old installer compatibility is not preserved.

## Success Criteria

- [ ] Readers identify this repo as dotfiles-only from README/source-of-truth.
- [ ] Shell-first bootstrap authority is superseded or moved out of this repo.
- [ ] `bin/dotlink` and profile manifests have clear first-slice ownership.
