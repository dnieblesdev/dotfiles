# Tasks: Split Dotfiles Bootstrap Identity

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | 450-700 |
| 400-line budget risk | High |
| Chained PRs recommended | Yes |
| Suggested split | PR 1: dotlink surface + manifests; PR 2: legacy bootstrap/controller deletion + docs |
| Delivery strategy | single-pr |
| Chain strategy | size-exception |

Decision needed before apply: Yes
Chained PRs recommended: Yes
Chain strategy: size-exception
400-line budget risk: High

### Suggested Work Units

| Unit | Goal | Likely PR | Notes |
|------|------|-----------|-------|
| 1 | Ship `bin/dotlink`, `dotlink/`, and declarative profile manifests | PR 1 | Base the review on the dotfiles repo; include link/status/verify safety tests. |
| 2 | Remove legacy bootstrap/controller surfaces and update docs | PR 2 | Base on PR 1 or a size-exception branch; include removal scans and authority docs. |

## Phase 1: Dotlink foundation

- [x] 1.1 Create `bin/dotlink` as the visible entrypoint and wire it to the new dotlink implementation area.
- [x] 1.2 Add `dotlink/manifest.sh` and profile manifest files to load declarative module/profile data safely.
- [x] 1.3 Define ownership/conflict helpers in `dotlink/` for repo-owned symlinks, foreign paths, and rollback on abort.

## Phase 2: Core split and deletions

- [x] 2.1 Implement `dotlink/dotlink.sh` for link/list/status/unlink/verify against profile manifests and symlink ownership rules.
- [x] 2.2 Delete `installer/install.sh` and `installer/dotlink`; remove any compatibility or fallback references.
- [x] 2.3 Delete `cmd/bootstrap-controller/`, `internal/controller/`, `bootstrap-controller`, and controller-only Go artifacts including `go.mod` if nothing else remains.

## Phase 3: Docs and source-of-truth wiring

- [x] 3.1 Update `README.md` to present the repo as dotfiles-only with `bin/dotlink` as the entry map.
- [x] 3.2 Update `docs/vision.md`, `docs/bootstrap-contract.md`, and `docs/decisions/` or the ADR that records why bootstrap split out.
- [x] 3.3 Add docs-only bootstrapper handoff text that names the sibling project boundary without implementing it.

## Phase 4: Verification and drift checks

- [x] 4.1 Add tests for profile manifest loading, conflict detection, and symlink ownership refusal in `dotlink/`.
- [x] 4.2 Verify `bin/dotlink` works in temp `$HOME` scenarios and that removed bootstrap paths no longer exist.
- [x] 4.3 Add drift scans that fail on stale authoritative references to `installer/install.sh`, `installer/dotlink`, `cmd/bootstrap-controller/`, and `internal/controller/`.

## Phase 5: Cleanup

- [x] 5.1 Remove stale bootstrap mentions from docs/source-of-truth files and ensure remaining references clearly mark the sibling bootstrapper as external.
- [x] 5.2 Confirm repository root no longer advertises shell bootstrap as authoritative in any surviving README or ADR text.
