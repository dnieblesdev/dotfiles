# Delta for project-source-of-truth

## MODIFIED Requirements

### Requirement: Shell-first bootstrap contract
The documentation system MUST state that dotfiles authority lives in this repository only for configuration modules, declarative profiles, and symlink lifecycle; shell-first bootstrap canonicality is no longer authoritative here. The system MUST describe any sibling bootstrapper as a separate future repository boundary and MUST NOT require compatibility for `installer/install.sh` or `installer/dotlink`. The system MUST state that `cmd/bootstrap-controller/`, `internal/controller/`, `bootstrap-controller`, and controller-only Go/TUI artifacts are removed or non-authoritative for this repository.
(Previously: shell-based installer behavior was canonical and Go/TUI was optional frontend behavior.)

#### Scenario: Reader checks bootstrap authority
- GIVEN a contributor reads bootstrap authority docs
- WHEN they look for the canonical surface
- THEN they see dotfiles-only authority for modules, profiles, and symlink lifecycle
- AND the old shell bootstrap path is not treated as authoritative here

#### Scenario: Legacy installer expectation
- GIVEN a reader expects old installer compatibility
- WHEN they consult the contract
- THEN no shim or preservation guarantee is required for `installer/install.sh` or `installer/dotlink`

#### Scenario: Go bootstrap controller expectation
- GIVEN a reader expects Go/TUI bootstrap-controller authority in this repository
- WHEN they consult the contract
- THEN `cmd/bootstrap-controller/`, `internal/controller/`, `bootstrap-controller`, and controller-only Go artifacts are removed or marked non-authoritative
- AND dotfiles authority remains limited to modules, declarative profiles, and symlink lifecycle

### Requirement: Stable source-of-truth document
The documentation system MUST maintain a stable vision/source-of-truth document that defines project purpose, boundaries, non-goals, and authority hierarchy.
(Previously: source-of-truth centered shell-first portable environment and bootstrap ownership.)

#### Scenario: New contributor needs orientation
- GIVEN a contributor needs the project intent
- WHEN they read the source-of-truth document
- THEN they can identify purpose, boundaries, and non-goals

#### Scenario: Scope dispute arises
- GIVEN a proposed change blurs the project boundary
- WHEN the source-of-truth document is consulted
- THEN it clarifies whether the change is in scope
