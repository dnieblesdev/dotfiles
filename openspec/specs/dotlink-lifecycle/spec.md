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

#### Scenario: Partial failure rolls back owned changes
- GIVEN dotlink creates one or more repository-owned symlinks during a link operation
- AND a later destination in the same operation conflicts or fails
- WHEN dotlink aborts the operation
- THEN it removes only the symlinks it created during that operation
- AND it leaves pre-existing repository-owned and non-owned paths unchanged

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
