# Proposal: Reconstruct Project Source of Truth

## Intent

Create a visible documentation source-of-truth so project direction is no longer reconstructed from commits, scattered docs, runtime code, and memory. The proposal defines the documentation family and authority boundaries; implementation will update production documentation while leaving runtime behavior unchanged.

## Scope

### In Scope
- Define a split documentation family: vision/constitution, bootstrap contract, operational installer guide, roadmap, and optional ADRs.
- Establish README as an entry map, not the architectural authority.
- Make shell-first canonicality explicit: `installer/install.sh` owns catalog, plan/apply/list, privileges, and signed state; Go/TUI remains optional frontend.

### Out of Scope
- Editing installer scripts, Go controller code, or runtime behavior.
- Changing bootstrap behavior, state semantics, privilege behavior, or Go/TUI protocol behavior.
- Reworking the installer architecture or changing PR delivery strategy.

## Capabilities

### New Capabilities
- `project-source-of-truth`: Governs the documentation family, authority hierarchy, shell-first bootstrap contract, README entry-point role, roadmap boundary, and optional ADR usage.

### Modified Capabilities
- None — no existing capability spec exists; current `openspec/specs/reconstruct-project-source-of-truth/exploration.md` is exploratory input, not a capability spec.

## Approach

Use the exploration recommendation: avoid one monolithic PRD. Define small docs with one job each: stable project intent, executable bootstrap contract, operational usage, future roadmap, and durable decisions. Keep implementation authority anchored in shell behavior while docs make that authority readable.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `openspec/changes/reconstruct-project-source-of-truth/proposal.md` | New | Proposal artifact for this phase. |
| `openspec/specs/project-source-of-truth/spec.md` | Future New | Capability spec expected in the spec phase. |
| `README.md`, `docs/vision.md`, `docs/bootstrap-contract.md`, `docs/installer.md`, `docs/roadmap.md`, `docs/decisions/` | Future Modified/New | Planned production documentation family for implementation. |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Split docs remain fragmented | Med | Require README map and explicit authority hierarchy. |
| Docs drift from installer behavior | Med | Name shell contract as canonical and mirror implementation boundaries. |
| Scope expands into runtime refactor | Low | Keep this change documentation-only. |

## Rollback Plan

Revert the documentation files and delete this change folder; remove the Engram artifact `sdd/reconstruct-project-source-of-truth/proposal` if abandoning the SDD trail. Since runtime files are unchanged, rollback has no installer behavior impact.

## Dependencies

- Exploration artifact: `sdd/reconstruct-project-source-of-truth/explore` and filesystem fallback exploration.

## Success Criteria

- [ ] Proposal identifies the new `project-source-of-truth` capability without placeholders.
- [ ] Proposal defines doc-family boundaries and shell-first authority without changing runtime behavior.
- [ ] Downstream spec/design phases can proceed without re-deciding the documentation structure.
