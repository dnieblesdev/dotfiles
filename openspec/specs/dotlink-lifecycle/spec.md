# Delta for dotlink-lifecycle

## ADDED Requirements

### Requirement: Visible dotlink entrypoint
The system MUST expose `bin/dotlink` as the user-facing entrypoint for dotfile linking and status operations.

#### Scenario: User discovers dotlink
- GIVEN a contributor inspects the repository root
- WHEN they look for the dotfile linker
- THEN `bin/dotlink` is present as the visible entrypoint
- AND the repo explains where the implementation lives

#### Scenario: Entry surface is separated
- GIVEN a reader follows the dotlink path
- WHEN they inspect the implementation boundary
- THEN the command behavior is owned by a dedicated dotlink area

### Requirement: Dotlink lifecycle operations
The system MUST support link, list, status, unlink, and verify semantics for repository-owned configuration links.

#### Scenario: Link and verify
- GIVEN a selected profile or module set
- WHEN dotlink links the requested files
- THEN the expected links are created
- AND verify reports success when links match the intended targets

#### Scenario: List, status, and unlink
- GIVEN existing dotfile links are present
- WHEN dotlink lists or checks status
- THEN it reports current link state without modifying files
- AND WHEN dotlink unlinks them
- THEN the links are removed without changing unrelated files

### Requirement: Dotlink ownership safety
The system MUST manage only symlinks that it can prove are repository-owned and MUST refuse conflicts instead of overwriting or removing non-owned paths.

#### Scenario: Existing regular file blocks linking
- GIVEN the desired destination already exists as a regular file
- WHEN dotlink links the selected module
- THEN dotlink refuses the operation with a conflict
- AND it does not overwrite, rename, or remove the existing file

#### Scenario: Foreign symlink blocks linking or unlinking
- GIVEN the desired destination is a symlink to a target outside the repository-owned module set
- WHEN dotlink links or unlinks the selected module
- THEN dotlink refuses the operation with a conflict
- AND it does not replace or remove the foreign symlink

#### Scenario: Removal survives a missing source
- GIVEN a repository-owned symlink was created for a module
- AND the declared source was moved or deleted afterwards
- WHEN the user runs dotlink unlink for that module
- THEN dotlink removes the symlink and reports which path it removed
- AND the missing source does not block removal, because ownership alone authorizes it

#### Scenario: Undescribed repository-owned symlink stays reachable
- GIVEN a repository-owned symlink exists whose destination no selected module accounts for
- WHEN dotlink unlink or status runs
- THEN dotlink reports it as `drift orphan` and unlink removes it
- AND foreign paths are still never touched

#### Scenario: A module with nothing to check is not reported as healthy
- GIVEN a known module is selected but resolves to no entry at all
- WHEN dotlink status or verify runs
- THEN it names the module and fails
- AND the read-only guarantee is preserved

#### Scenario: Broken symlink is not assumed owned
- GIVEN the desired destination is a broken symlink
- WHEN dotlink evaluates ownership
- THEN dotlink treats it as a conflict unless its recorded or resolvable target is repository-owned
- AND it never removes a broken non-owned symlink

#### Scenario: Partially linked module is detected
- GIVEN only some expected destinations for a module are repository-owned symlinks
- WHEN dotlink status or verify runs
- THEN it reports the module as partial or drifted
- AND it identifies conflicts without modifying paths

#### Scenario: Partial failure preserves successes and continues
- GIVEN a selected destination conflicts or fails during linking
- WHEN dotlink processes the selected entries
- THEN it reports the failed entry and attempts all later safe entries
- AND it retains earlier and later successful links
- AND it cleans only incomplete changes created for the failed entry
- AND it leaves pre-existing repository-owned and non-owned paths unchanged
- AND it prints created/unchanged/failed counts and exits 1 if any entry failed

#### Scenario: Verify and status detect drift
- GIVEN a previously linked destination no longer points at the intended repository target
- WHEN dotlink status or verify runs
- THEN it reports drift or conflict
- AND it does not repair, remove, or overwrite the path unless the user runs an explicit supported lifecycle operation

### Requirement: Dotlink must not provision software
The system MUST NOT install applications, tools, runtimes, or perform OS provisioning during dotlink operations.

#### Scenario: Link workflow stays bounded
- GIVEN a user runs dotlink for configuration management
- WHEN dotlink executes
- THEN only dotfile link lifecycle actions occur
- AND no package, runtime, or OS provisioning is started

#### Scenario: Broken legacy installer is not preserved
- GIVEN a user expects compatibility for `installer/install.sh` or `installer/dotlink`
- WHEN they inspect the new contract
- THEN no compatibility shim is required for either old installer entrypoint
