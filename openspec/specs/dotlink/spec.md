# dotlink Structured Link Report Delta

## ADDED Requirements

### Requirement: Opt-in structured report for link

The system SHALL accept `--report=json` and `--report=json` only as an option of `bin/dotlink link`. When the option is absent, the system SHALL use human-oriented output. Both modes SHALL attempt all safe selected entries, retain successes after individual failures, and finish with created/unchanged/failed counts (stderr in JSON mode).

#### Scenario: Legacy link invocation

- **WHEN** a user invokes `bin/dotlink link` without `--report`
- **THEN** the system emits human-oriented progress, per-entry errors, and a final summary

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
The former `rolled_back` outcome is no longer emitted for earlier successes: later failures do not remove successful links.

#### Scenario: Already-linked target

- **WHEN** a selected entry already links to its requested source
- **THEN** its reported outcome is `unchanged`

#### Scenario: Later conflict preserves successes and does not stop execution

- **WHEN** an earlier entry is created and a later entry fails
- **THEN** the failed entry has outcome `failed` and an explicit cause
- **AND THEN** the earlier success remains `changed` and stays linked
- **AND THEN** later safe entries are attempted and reported

### Requirement: Aggregate outcome, failure, and rollback reporting

The report SHALL include an aggregate `status` that is `success` only when all selected entries complete without failure; otherwise it SHALL be `failed`. The existing `rollback` object SHALL describe cleanup of incomplete failed-entry changes only, never removal of earlier successes. Its completed flag SHALL be false if any attempted cleanup failed.

For any failure, the report SHALL include a `failure` object identifying the first failed entry/module and a machine-readable cause code; every later failure SHALL also appear in its ordered entry. If failure occurs while processing a link entry, `failure` SHALL also include that entry's `source` and `target`, and the corresponding entry SHALL have outcome `failed`. If selection fails before an entry can be resolved, `failure` SHALL identify the affected module when available and use `null` for unavailable source or target values.

#### Scenario: Conflict failure

- **WHEN** a selected target is a regular file, directory, foreign symlink, or unproven broken symlink
- **THEN** the aggregate status is `failed`
- **AND THEN** the report identifies the failed entry and a conflict cause
- **AND THEN** cleanup metadata identifies only incomplete failed-entry changes removed, if any
- **AND THEN** all other safe selected entries are attempted

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
