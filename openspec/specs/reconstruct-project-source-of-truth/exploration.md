# Source of truth reconstruction exploration

## Exploration: reconstruct-project-source-of-truth

### Current State
Superseded by `split-dotfiles-bootstrap-identity`: this repository is now authoritative only for dotfiles configuration modules, declarative profiles, and repository-owned symlink lifecycle behavior. Package installation, runtime setup, OS bootstrap, and controller behavior are external to this repository.

### Affected Areas
- `README.md` — points readers toward the dotfiles-only source of truth.
- `docs/removed-installer.md` — removed from local authority by `split-dotfiles-bootstrap-identity`.
- `docs/vision.md` — would define the canonical project intent and boundaries.
- `docs/bootstrap-contract.md` — removed from local authority by `split-dotfiles-bootstrap-identity`.
- `docs/roadmap.md` — would separate near-term cleanup from the authoritative contract.
- `docs/decisions/` — optional ADRs for durable dotfiles-only repository boundaries.
- Historical note, superseded by `split-dotfiles-bootstrap-identity`: `installer/install.sh`, `installer/lib/*.sh`, `cmd/bootstrap-controller/main.go`, and `internal/controller/adapter.go` were the bootstrap implementation sources for this archived reconstruction phase and are no longer authoritative in this dotfiles repository.

### Approaches
1. **Single monolithic PRD/doc** — Put vision, contract, roadmap, and decisions into one large document.
   - Pros: one place to read; easy to create quickly; obvious “single source” label.
   - Cons: high cognitive load; mixes stable policy with changing roadmap; harder review and drift control; encourages bloated edits.
   - Effort: Low

2. **Split constitution/contract/roadmap/ADRs** — Separate the immutable project intent, dotfiles-only local authority, the forward roadmap, and durable decisions.
   - Pros: lower cognitive load; clearer review boundaries; stable docs can stay small; roadmap can change without rewriting policy; easier to keep docs aligned with repository authority boundaries.
   - Cons: more files to maintain; requires a clear top-level index so readers do not get lost.
   - Effort: Medium

### Recommendation
Use the split structure. It best matches the repo’s current architecture: local authority is limited to dotfiles modules, declarative profiles, and symlink lifecycle behavior. Separate documents reduce drift because each file has one job, and reviewers can verify policy, boundaries, and roadmap independently.

### Risks
- The new doc family could still drift unless the top-level index explicitly names the dotfiles-only authority boundary.
- If the docs are split without a strong entry point, the repository may feel more fragmented before it feels clearer.

### Ready for Proposal
Yes — proceed with a proposal that defines the doc family and top-level indexing rules before editing production docs.
