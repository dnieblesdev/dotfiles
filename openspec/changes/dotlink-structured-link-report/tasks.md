# Tasks: structured link report

## 1. Define report-mode CLI and result model

- [ ] 1.1 Update the link-command argument handling to accept only `--report=json`; reject unsupported report values with exit code `2`.
- [ ] 1.2 Keep report mode scoped to `link`; preserve option handling for `list`, `status`, `unlink`, and `verify`.
- [ ] 1.3 Introduce execution-result records for selected modules, per-entry source/target/outcome, failure context, and rollback cleanup state.

## 2. Preserve link safety while recording results

- [ ] 2.1 Record `unchanged` for existing correct links and `changed` only for links that remain after a successful operation.
- [ ] 2.2 On conflict or operational failure, record the failed entry and machine-readable cause while preserving exit code `1`.
- [ ] 2.3 Reuse the existing rollback scope, convert removed creations to `rolled_back`, and report removed links and invocation-created directories.
- [ ] 2.4 Represent pre-entry selection failures, including unknown modules, in the aggregate failure context without performing link side effects.

## 3. Render the JSON v1 contract

- [ ] 3.1 Implement shell-safe JSON encoding without adding a runtime dependency.
- [ ] 3.2 Emit exactly one JSON document on stdout in report mode with `schema_version`, ordered `modules`, aggregate `status`, ordered `entries`, `failure`, and `rollback`.
- [ ] 3.3 Send report-mode progress and human diagnostics to stderr; leave non-report output unchanged.

## 4. Add Bash regression coverage

- [ ] 4.1 Add tests for successful multi-module report ordering, schema version, entry fields, and `changed` outcomes.
- [ ] 4.2 Add no-op tests for `unchanged`, `success`, and no rollback.
- [ ] 4.3 Add failure/rollback tests proving failed cause reporting, `rolled_back` conversion, cleanup metadata, JSON-only stdout, stderr diagnostics, and exit code `1`.
- [ ] 4.4 Add CLI validation tests for unsupported report values, non-link use, and unknown modules with preserved exit codes and no side effects.
- [ ] 4.5 Add JSON-escaping fixture coverage where supported by the existing Bash harness, plus legacy link and unchanged `status`/`verify` regression checks.

## 5. Validate the future implementation

- [ ] 5.1 Run `make check`.
- [ ] 5.2 Run `make test`.
- [ ] 5.3 Run `make verify`.
- [ ] 5.4 Run `make all` as the final combined quality gate.

## Delivery notes

- This is a single focused change to the dotlink link-report contract; no provisioning or bootstrap work belongs in this repository.
- `dbootstrap` is a downstream consumer of the JSON contract only. Do not modify it as part of these tasks.
