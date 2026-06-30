# Tasks: Reconstruct Project Source of Truth

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | 280-420 |
| 400-line budget risk | Medium |
| Chained PRs recommended | No |
| Suggested split | Single PR |
| Delivery strategy | single-pr |
| Chain strategy | pending |

Decision needed before apply: Yes
Chained PRs recommended: No
Chain strategy: pending
400-line budget risk: Medium

### Suggested Work Units

| Unit | Goal | Likely PR | Notes |
|------|------|-----------|-------|
| 1 | Rebuild the source-of-truth doc set and navigation map | PR 1 | Base on main; include docs + link validation only. |

## Phase 1: Foundation / Documentation Architecture

- [x] 1.1 Create `docs/vision.md` as the stable authority doc: purpose, boundaries, non-goals, and doc hierarchy.
- [x] 1.2 Create `docs/bootstrap-contract.md` to define shell-first canonicality and Go/TUI as optional frontend.
- [x] 1.3 Create `docs/roadmap.md` with active/deferred work only so policy stays out of roadmap prose.
- [x] 1.4 Add a lightweight ADR decision point: create `docs/decisions/README.md` or `docs/decisions/adr-0001-shell-first-canonicality.md` if the bootstrap contract does not fully capture the canonicality decision.

## Phase 2: Entry Map and Cross-Linking

- [x] 2.1 Update `README.md` into a short entry map that points to `docs/vision.md`, `docs/bootstrap-contract.md`, `docs/installer.md`, and `docs/roadmap.md`.
- [x] 2.2 Update `docs/installer.md` to stay operational-only and defer authority to `docs/bootstrap-contract.md`.
- [x] 2.3 Add explicit link hierarchy notes so deeper docs override README summaries when readers encounter conflicts.
- [x] 2.4 Verify `README.md` does not duplicate installer behavior, roadmap items, or policy language.

## Phase 3: Verification

- [x] 3.1 Review all new/updated docs for shell-first consistency with `installer/install.sh` as the canonical behavior source.
- [x] 3.2 Check that each doc has one job, short sections, and clear handoff links for contributor navigation.
- [x] 3.3 Validate the ADR gate decision: confirm whether shell-first canonicality needs the dedicated ADR file or is sufficiently covered in `docs/bootstrap-contract.md`.

## Phase 4: Cleanup / Polish

- [x] 4.1 Remove any duplicated authority statements from README or installer docs after cross-linking is in place.
- [x] 4.2 Tighten headings, labels, and link text for scan-friendly review paths.
