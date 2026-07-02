# Design: Split Dotfiles Bootstrap Identity

## Technical Approach

Make the repo boundary explicit in one destructive but small first pass: this repo owns dotfile modules, declarative shell-data profiles, and symlink lifecycle through `bin/dotlink`; it no longer owns bootstrap/install execution. Remove old shell installer/bootstrap entrypoints and remove the Go bootstrap-controller code now. The sibling bootstrapper starts as docs-only; implementation can be recovered or migrated deliberately from git history later. There is no quarantine, compatibility shim, or installer-path fallback.

## Architecture Decisions

| Decision | Choice | Alternatives considered | Rationale |
|----------|--------|-------------------------|-----------|
| Repo authority | Dotfiles-only authority: modules, profiles, symlink lifecycle. | Keep shell-first bootstrap as canonical here. | The proposal/spec require replacing bootstrap authority with dotfiles-only source of truth. |
| Legacy bootstrap removal | Delete `installer/install.sh`, `installer/dotlink`, Go controller code, and controller-only Go artifacts in this pass. | Quarantine docs-only, leave dead Go code, or add shims. | User resolved blockers with “Eliminar ambos”; keeping compatibility would preserve duplicate authority and stale tests. |
| Entry surface | Create `bin/dotlink` as the stable user-facing command. | Keep installer paths as wrappers. | A root command is discoverable and avoids implying installer ownership. |
| Profiles | Add restricted declarative shell data under `profiles/`; manifests only contain validated assignment-only metadata/module selections. | Source arbitrary `.sh` scripts or put provisioning/executable setup logic in profiles. | Profiles select dotfile modules only; package/runtime provisioning belongs outside this repo, and `.sh` data must not become an execution escape hatch. |
| Bootstrapper handoff | Add docs-only handoff documentation. | Implement sibling bootstrapper now. | Full bootstrapper implementation is out of scope and can be recovered from git history later. |

## Data Flow

```text
bin/dotlink ──→ dotlink/*.sh ──→ profiles/*.sh data
     │              │                    │
     │              └──→ repo modules ───┘
     └── link/list/status/unlink/verify only

bootstrap implementation: out of repo; docs-only handoff now
```

## File Changes

| File | Action | Description |
|------|--------|-------------|
| `bin/dotlink` | Create | Visible entrypoint; delegates to dotlink implementation. |
| `dotlink/dotlink.sh` | Create | Owns link/list/status/unlink/verify, module/profile resolution, and safety checks. |
| `dotlink/manifest.sh` | Create | Loads declarative profile data and validates known modules. |
| `profiles/base.sh` | Create | Default module selection, e.g. `bash`, `git`, `env`. |
| `profiles/interactive.sh` | Create | Optional interactive module selection, e.g. `zsh`, `config`. |
| `installer/install.sh` | Delete | Old bootstrap entrypoint removed; no quarantine and no shim. |
| `installer/dotlink` | Delete | Replaced by `bin/dotlink`; no installer-path compatibility. |
| `cmd/bootstrap-controller/` | Delete | Go bootstrap controller removed from this repo. |
| `internal/controller/` | Delete | Controller-only protocol/adapter code removed with the Go controller. |
| `go.mod` | Delete if controller-only | Remove Go module artifact if no non-controller Go code remains. |
| `README.md` | Modify | Replace bootstrap quick start with dotfiles-only entry map and dotlink examples. |
| `docs/vision.md` | Modify | Declare dotfiles-only purpose, boundaries, non-goals, and authority order. |
| `docs/bootstrap-contract.md` | Modify | Supersede local bootstrap contract and point to docs-only sibling handoff. |
| `docs/installer.md` | Modify/Delete | Remove operational installer authority; keep only non-authoritative migration note if retained. |
| `docs/bootstrapper-handoff.md` | Create | Docs-only sibling bootstrapper scaffold and recovery-from-history guidance. |
| `docs/decisions/adr-0001-shell-first-canonicality.md` | Modify | Mark superseded by split ADR. |
| `docs/decisions/adr-0002-dotfiles-bootstrap-split.md` | Create | Record bootstrap authority removal and no-shim decision. |

## Interfaces / Contracts

```bash
bin/dotlink link [--profile NAME] [MODULE...]
bin/dotlink list [--profile NAME]
bin/dotlink status [--profile NAME] [MODULE...]
bin/dotlink unlink [--profile NAME] [MODULE...]
bin/dotlink verify [--profile NAME] [MODULE...]
```

Profile manifests are declarative shell data only. Although they use `.sh` syntax for shell-native arrays, the loader contract is restricted assignment-only evaluation: validate first, accept only known profile variables, and reject command substitutions, function definitions, aliases, control flow, external command invocations, file mutations, package installation, and bootstrap/provisioning logic before anything can execute.

```bash
DOTLINK_PROFILE_MODULES=(bash git env)
```

Manifests MUST NOT be documented or treated as executable provisioning scripts. They MUST NOT install packages, invoke bootstrap commands, mutate `$HOME`, define functions, or execute provisioning logic.

Dotlink ownership invariants:

- Dotlink manages only symlinks it can prove are repository-owned and expected for the selected module/profile.
- Existing regular files, directories, foreign symlinks, and broken symlinks without provable repo ownership are conflicts; dotlink refuses them and never overwrites, renames, or removes them.
- `status` and `verify` are read-only drift detectors: they report missing links, wrong targets, foreign paths, broken/non-owned symlinks, and partially linked modules without repairing them.
- `unlink` removes only proven repo-owned symlinks and leaves all non-owned paths untouched.
- If `link` partially succeeds and then fails, rollback removes only symlinks created during that operation; pre-existing repo-owned links and all non-owned paths remain unchanged.

## Testing Strategy

| Layer | What to Test | Approach |
|-------|-------------|----------|
| Unit | Profile/module resolution and unknown input rejection. | Shell fixtures around `dotlink/manifest.sh`. |
| Integration | link/list/status/unlink/verify against temp `$HOME`. | Run `bin/dotlink` with fixture modules and profiles. |
| Safety | Ownership and drift invariants for regular files, foreign symlinks, broken symlinks, partial modules, and rollback after partial failure. | Shell integration fixtures against temp `$HOME`; assert conflicts refuse mutation and rollback touches only links created in the failed operation. |
| Docs | No stale installer/bootstrap authority. | Review docs and scan for removed/renamed bootstrap surfaces and authority terms: `installer/install.sh`, `installer/dotlink`, `cmd/bootstrap-controller/`, `internal/controller/`, `bootstrap-controller`, Go/TUI authority, shell-first bootstrap, installer docs, and ADR references. |
| Go | Stale bootstrap-controller tests. | Remove controller-only Go tests/code/module artifacts; scan for `cmd/bootstrap-controller/`, `internal/controller/`, `bootstrap-controller`, and Go/TUI authority references because they are no longer part of verification for this repo. |

## Migration / Rollout

No runtime migration required. This is a breaking source-boundary cleanup: remove old bootstrap entrypoints and controller code, add dotlink/profile surface, update docs/ADRs in the same work unit, and rely on git history for future bootstrapper recovery. Rollback is a normal git revert.

## Open Questions

None.
