# Add an opt-in structured dotlink link report

`bin/dotlink link --report=json` will give automation a stable, machine-readable result without changing the established human-oriented CLI. This lets a downstream consumer such as `dbootstrap` make reliable decisions without parsing terminal text.

## Intent

Introduce an opt-in, schema-versioned JSON report for the `link` command. The report must accurately represent successful no-ops, created links, failures, and rollback so consumers never mistake a partial attempt for success.

## Scope

- Add `--report=json` only to `bin/dotlink link`.
- Emit one JSON document on stdout in report mode; send diagnostics to stderr.
- Report selected modules deterministically and include per-link source, target, outcome, failure cause, aggregate status, and rollback metadata.
- Preserve the existing link safety and exit-code behavior.
- Add Bash regression coverage for normal, no-op, failure, and rollback report cases.

## Out of scope

- Provisioning, package or tool installation, remote acquisition, and OS setup.
- Changes to `dbootstrap` or any bootstrap behavior; it is only an intended future consumer.
- Structured output for `list`, `status`, `unlink`, or `verify`.
- Any behavior or output change when `--report` is absent.
- Changes to `status` or `verify` scope or semantics.

## Affected areas

| Area | Change |
|---|---|
| `bin/dotlink` / `dotlink/dotlink.sh` | Parse the link-only report option, isolate human and JSON output, and retain operation results for reporting. |
| `dotlink/tests/` | Add JSON contract and rollback regression coverage using the existing Bash harness. |
| `openspec/changes/dotlink-structured-link-report/` | Planning artifacts for the future implementation. |

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| Automation treats a rolled-back partial operation as successful. | Require a non-success aggregate status, explicit failure cause, and rollback metadata. |
| JSON is malformed by shell-special paths or diagnostic output. | Define stdout/stderr separation and test escaping plus the single-document invariant. |
| New parsing changes legacy behavior. | Keep report mode opt-in and regression-test legacy output and exit codes. |
| Link safety regresses during result collection. | Preserve conflict refusal and rollback rules; test conflict and rollback paths. |

## Rollback

The future implementation is reversible by removing the `--report=json` parsing and reporting path. Because the option is opt-in and default behavior is unchanged, callers that do not request it are unaffected. A consumer can stop requesting the option if compatibility problems arise.

## Success criteria

- `bin/dotlink link --report=json MODULE...` produces exactly one valid, schema-versioned JSON document on stdout.
- The document deterministically identifies selected modules and every processed link entry with `module`, `source`, `target`, and the required outcome.
- A failure identifies its entry and cause; rollback state prevents a partial attempt from being represented as success.
- Exit codes remain `0` for successful/no-op linking, `1` for operational, unknown-module, or conflict failures, and `2` for CLI errors.
- Calls without `--report` retain their current stdout, stderr, scope, and behavior.
- `make check`, `make test`, `make verify`, and `make all` pass for the implemented change.
