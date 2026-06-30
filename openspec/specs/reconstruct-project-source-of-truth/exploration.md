# Source of truth reconstruction exploration

## Exploration: reconstruct-project-source-of-truth

### Current State
The repository is already functionally shell-first. `installer/install.sh` owns the bootstrap catalog, plan/apply/list behavior, privilege boundaries, and signed state under `$XDG_STATE_HOME`. The Go controller is optional: it handshakes with the shell contract, loads the shell-owned catalog, and falls back to shell execution when the protocol or controller path fails. Documentation reflects parts of this, but the intent is spread across `README.md` and `docs/installer.md` instead of living in one visible source of truth.

### Affected Areas
- `README.md` — currently advertises bootstrap status and needs to align with the reconstructed source of truth.
- `docs/installer.md` — currently contains the deepest contract details, but only as an installer note, not a governing project source of truth.
- `docs/vision.md` — would define the canonical project intent and boundaries.
- `docs/bootstrap-contract.md` — would capture the shell-first contract and UI fallback rules.
- `docs/roadmap.md` — would separate near-term cleanup from the authoritative contract.
- `docs/decisions/` — optional ADRs for sticky choices such as shell-first canonicality and optional Go frontend.
- `installer/install.sh`, `installer/lib/*.sh`, `cmd/bootstrap-controller/main.go`, `internal/controller/adapter.go` — implementation sources that the docs must mirror, but are not to be changed in this phase.

### Approaches
1. **Single monolithic PRD/doc** — Put vision, contract, roadmap, and decisions into one large document.
   - Pros: one place to read; easy to create quickly; obvious “single source” label.
   - Cons: high cognitive load; mixes stable policy with changing roadmap; harder review and drift control; encourages bloated edits.
   - Effort: Low

2. **Split constitution/contract/roadmap/ADRs** — Separate the immutable project intent, the executable bootstrap contract, the forward roadmap, and durable decisions.
   - Pros: lower cognitive load; clearer review boundaries; stable docs can stay small; roadmap can change without rewriting policy; easier to keep docs aligned with shell-vs-TUI authority boundaries.
   - Cons: more files to maintain; requires a clear top-level index so readers do not get lost.
   - Effort: Medium

### Recommendation
Use the split structure. It best matches the repo’s real architecture: a shell canonical core with an optional Go frontend. Separate documents reduce drift because each file has one job, and reviewers can verify policy, contract, and roadmap independently.

### Risks
- The new doc family could still drift from `installer/install.sh` unless the top-level index explicitly names the shell contract as canonical.
- If the docs are split without a strong entry point, the repository may feel more fragmented before it feels clearer.

### Ready for Proposal
Yes — proceed with a proposal that defines the doc family and top-level indexing rules before editing production docs.
