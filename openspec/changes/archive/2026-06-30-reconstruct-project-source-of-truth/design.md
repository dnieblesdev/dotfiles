# Design: Reconstruct Project Source of Truth

## Technical Approach

Implement this as a documentation-only source-of-truth family. `README.md` becomes the repository entry map; stable authority moves into focused docs under `docs/`. The design follows the `project-source-of-truth` spec: deeper authority docs win over README summaries, shell installer behavior remains canonical, roadmap items stay separate from stable policy, and durable decisions may move into ADRs.

## Architecture Decisions

| Decision | Choice | Alternatives considered | Rationale |
|----------|--------|--------------------------|-----------|
| Authority split | Use `docs/vision.md`, `docs/bootstrap-contract.md`, `docs/installer.md`, `docs/roadmap.md`, optional `docs/decisions/` | One monolithic PRD; README as full authority | Small single-purpose docs reduce drift and review load. README should orient, not duplicate architecture. |
| Bootstrap authority | Document `installer/install.sh` and shell libraries as canonical; Go controller/TUI as optional frontend | Treat Go/TUI as equal source; document only UI behavior | Current code invokes shell from Go and falls back to shell. The shell owns catalog/list/apply/state behavior, so docs must reflect that boundary. |
| Review shape | Modify production docs in one documentation PR, keeping sections short and link-driven | Large narrative rewrite | The requested single PR can stay under the 800-line review budget if content is concise and avoids duplicating installer internals. |
| Decision records | Create ADRs only for durable architectural choices that should not live in roadmap | Put every thought into ADRs; skip ADRs entirely | Optional ADRs preserve important choices without turning active/deferred work into policy. |

## Data Flow

Documentation readers should move from broad orientation to authoritative detail:

```text
README.md ──→ docs/vision.md ──→ docs/bootstrap-contract.md
    │               │                       │
    │               └──→ docs/roadmap.md    └──→ docs/installer.md
    └──→ docs/decisions/ (only for durable decisions)
```

Implementation authority remains:

```text
installer/install.sh + installer/lib/*.sh ── canonical behavior
cmd/bootstrap-controller + internal/controller ── optional frontend/adapter
docs/bootstrap-contract.md ── readable contract for shell-owned behavior
```

## File Changes

| File | Action | Description |
|------|--------|-------------|
| `README.md` | Modify later | Convert to entry map with short status, install path, and links to authoritative docs. |
| `docs/vision.md` | Create later | Stable project purpose, boundaries, non-goals, and authority hierarchy. |
| `docs/bootstrap-contract.md` | Create later | Shell-first bootstrap contract: catalog, plan/apply/list, privileges, signed/advisory state, fallback behavior. |
| `docs/installer.md` | Modify later | Keep operational installer usage and troubleshooting; link to contract for authority. |
| `docs/roadmap.md` | Create later | Active/deferred work only; not stable policy. |
| `docs/decisions/` | Create if needed | ADRs for durable architecture decisions, such as shell-first canonicality if not fully captured in `vision`/`bootstrap-contract`. |

## Interfaces / Contracts

No runtime interfaces change. Documentation contract:

- README MUST link to authority docs and avoid restating full architecture.
- If README conflicts with `docs/vision.md` or `docs/bootstrap-contract.md`, the deeper doc wins.
- `docs/bootstrap-contract.md` MUST name shell behavior as canonical and Go/TUI as optional frontend.
- Roadmap content MUST NOT redefine stable policy.

## Testing Strategy

| Layer | What to Test | Approach |
|-------|-------------|----------|
| Unit | Not applicable | Documentation-only change. |
| Integration | Link and authority consistency | Manually verify README links and cross-doc authority statements. |
| E2E | Contributor orientation path | Read from README to vision, bootstrap contract, installer guide, and roadmap without needing code spelunking. |

## Migration / Rollout

No migration required. Roll out as a single documentation PR. Runtime behavior, installer scripts, and Go controller code remain unchanged.

## Open Questions

- [ ] Should shell-first canonicality be captured as a dedicated ADR, or is `docs/bootstrap-contract.md` sufficient for now?
