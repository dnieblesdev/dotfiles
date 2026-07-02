# Dotfiles identity split exploration

## Exploration: split-dotfiles-bootstrap-identity

### Current State
The repository still mixes two responsibilities. The shell installer and Go controller own bootstrap concerns today: OS/package/runtime installation, privilege handling, plan/apply/list state, optional TUI entry, and clone/update of the repo itself. In parallel, the repo already contains the pieces that should remain in a true dotfiles project: configuration modules, linking behavior, and documentation about project boundaries. The current docs also still encode shell-first bootstrap canonicality, which is now the wrong authority for the dotfiles repo once bootstrap is split into a sibling project.

### Affected Areas
- `installer/install.sh` — bootstrap orchestration, runtime/tool installation, clone/update, privilege/state logic; should move out of dotfiles repo.
- `cmd/bootstrap-controller/main.go` — optional frontend/controller for bootstrap; belongs with the future bootstrapper.
- `internal/controller/*.go` — controller contract and validation for bootstrap; belongs with the future bootstrapper.
- `docs/vision.md` — currently defines repo scope but still includes bootstrap-era assumptions; must become dotfiles-only.
- `docs/bootstrap-contract.md`, `docs/installer.md`, `docs/decisions/adr-0001-shell-first-canonicality.md` — current bootstrap authority docs; should be migrated, deprecated, or replaced by split-boundary docs.
- `README.md` — must become a dotfiles entry map, not a bootstrap launcher or architecture summary.
- `openspec/specs/project-source-of-truth/spec.md` — existing authority model will need revision because shell-first bootstrap is superseded for this repo.

### Approaches
1. **Extract bootstrap into sibling repo, keep dotfiles repo as module/link catalog** — move bootstrap code and bootstrap authority docs to the new project, leaving dotlink/profile/module responsibilities here.
   - Pros: clean boundary; removes identity drift; matches user intent; easier to reason about review scope.
   - Cons: requires coordination across repos; docs and links must be updated carefully.
   - Effort: High

2. **Keep bootstrap code here but relabel it as optional tooling** — preserve existing files and simply narrow the README/docs.
   - Pros: less immediate file movement.
   - Cons: preserves the wrong topology; invites more drift; contradicts the requested dotfiles-only identity.
   - Effort: Medium

### Recommendation
Take the extract-and-rehome path. This repo should become the dotfiles authority: modules, profiles, linking, verification, and assets. The new sibling bootstrapper should own environment detection, installs, sparse checkout, logging/state, and optional TUI. The old shell-first canonicality decision is only valid inside that new bootstrapper boundary; here it should be treated as superseded, not patched.

### Risks
- Partial migration could leave duplicate authority docs in both repos.
- If `dotlink` is not elevated to the repo core, the new boundary may still feel bootstrap-centric.
- Consumers may continue to follow old shell-first docs unless the split is explicitly recorded in ADR/spec form.

### Ready for Proposal
Yes — the next step is a proposal that names the repo split, defines dotfiles-only scope, and records bootstrap canonicality as belonging to the sibling project.
