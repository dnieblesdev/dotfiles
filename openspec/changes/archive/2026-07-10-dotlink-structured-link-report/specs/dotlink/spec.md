# dotlink Structured Link Report Delta

## ADDED Requirements

### Requirement: Opt-in structured report for link

The system SHALL accept `--report=json` and `--report=json` only as an option of `bin/dotlink link`. When the option is absent, the system SHALL preserve the existing CLI parsing, stdout, stderr, link behavior, and exit-code semantics.

#### Scenario: Legacy link invocation

- **WHEN** a user invokes `bin/dotlink link` without `--report`
- **THEN** the system preserves its existing human-oriented behavior and output

#### Scenario: Report option on another command

- **WHEN** a user supplies `--report=json` to `list`, `status`, `unlink`, or `verify`
- **THEN** the command is rejected as an unknown CLI option with exit code `2`
- **AND THEN** the behavior of those commands remains otherwise unchanged

### Requirement: JSON transport contract

When `link --report=json` is requested, the system SHALL write exactly one complete JSON document, followed only by its terminating newline, to stdout. It SHALL write human diagnostics only to stderr and SHALL not write human progress messages to stdout. The document SHALL include `schema_version` with the initial supported value `1`.

#### Scenario: Successful reported link

- **WHEN** a reported link operation succeeds
- **THEN** stdout contains exactly one parseable JSON document with `schema_version: 1`
- **AND THEN** stdout contains no human-oriented messages

#### Scenario: Reported operational failure

- **WHEN** a reported link operation encounters a conflict or operational failure
- **THEN** stdout still contains exactly one parseable JSON document
- **AND THEN** human diagnostics, if any, are written only to stderr

### Requirement: Deterministic link result report

The JSON document SHALL contain an ordered `modules` array for the selected modules and an ordered `entries` array for processed link entries. Module order SHALL match resolved selection order. Entry order SHALL be deterministic: module order first, then the existing deterministic source-entry traversal order. Every entry SHALL include `module`, `source`, `target`, and `outcome`.

An entry outcome SHALL be one of:

- `changed`: the symlink was created and remains after the command finishes.
- `unchanged`: the target already linked to the requested source and was not modified.
- `failed`: the entry could not be linked because of a conflict or operational cause.
- `rolled_back`: the symlink was created in this invocation and was removed because a later failure caused rollback.

#### Scenario: Already-linked target

- **WHEN** a selected entry already links to its requested source
- **THEN** its reported outcome is `unchanged`

#### Scenario: Later conflict rolls back an earlier creation

- **WHEN** an earlier entry is created and a later entry fails
- **THEN** the failed entry has outcome `failed` and an explicit cause
- **AND THEN** every earlier link removed by rollback has outcome `rolled_back`
- **AND THEN** no rolled-back entry is represented as `changed`

### Requirement: Aggregate outcome, failure, and rollback reporting

The report SHALL include an aggregate `status` that is `success` only when all selected entries complete without failure and no rollback occurs; otherwise it SHALL be `failed`. It SHALL include a `rollback` object stating whether rollback was attempted and completed, plus the targets removed and parent directories removed when applicable.

For any failure, the report SHALL include a `failure` object with the failed module and a machine-readable cause code. If failure occurs while processing a link entry, `failure` SHALL also include that entry's `source` and `target`, and the corresponding entry SHALL have outcome `failed`. If selection fails before an entry can be resolved, `failure` SHALL identify the affected module when available and use `null` for unavailable source or target values.

#### Scenario: Conflict failure

- **WHEN** a selected target is a regular file, directory, foreign symlink, or unproven broken symlink
- **THEN** the aggregate status is `failed`
- **AND THEN** the report identifies the failed entry and a conflict cause
- **AND THEN** rollback metadata identifies links and directories removed by this invocation, if any

#### Scenario: No-op success

- **WHEN** all selected targets are already correctly linked
- **THEN** the aggregate status is `success`
- **AND THEN** all entries have outcome `unchanged`
- **AND THEN** rollback is not attempted

### Requirement: Exit-code compatibility

Report mode SHALL preserve link exit codes: `0` for successful operations, including no-op operations; `1` for operational failures, unknown modules, and conflicts; and `2` for CLI errors. The JSON aggregate status SHALL not override the process exit code.

#### Scenario: Invalid report value

- **WHEN** a user invokes `bin/dotlink link --report=unsupported MODULE`
- **THEN** the command exits with code `2`
- **AND THEN** it does not perform linking

#### Scenario: Reported conflict

- **WHEN** a reported link operation fails due to a conflict
- **THEN** the command exits with code `1`
- **AND THEN** the JSON aggregate status is `failed`
