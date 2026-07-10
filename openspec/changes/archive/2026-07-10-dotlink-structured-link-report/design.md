# Design: structured link report

## Decision

Add a link-only `--report=json` mode that records link decisions as structured data and renders one final JSON document after the operation. Keep the existing human path intact when no report option is present.

## Data flow

1. Parse `link --report=json` while retaining current profile/explicit-module validation and exit codes.
2. Resolve modules using the existing selection rules; retain their order in the report.
3. For each deterministic source/target entry, record `unchanged`, `changed`, or `failed` as the existing safety checks and link operation run.
4. On a failure, run the existing rollback policy, convert every created-and-removed entry to `rolled_back`, and record removed links/directories.
5. Render the single JSON document to stdout, then return the existing operation exit code. Route human progress and diagnostics to stderr in report mode.

## Report schema v1

```json
{
  "schema_version": 1,
  "modules": ["bash", "git"],
  "status": "success",
  "entries": [
    {
      "module": "bash",
      "source": "/repo/bash/.bashrc",
      "target": "/home/user/.bashrc",
      "outcome": "changed"
    }
  ],
  "failure": null,
  "rollback": {
    "attempted": false,
    "completed": false,
    "removed_targets": [],
    "removed_directories": []
  }
}
```

For a failed entry, add a `cause` object to the entry and set the top-level `failure` object to the same module/source/target/cause context. `cause.code` is a stable machine-oriented category (for example `conflict`, `unknown_module`, `parent_conflict`, or `link_error`); `cause.message` is diagnostic text. Selection failures that have no source/target use JSON `null` for those fields in `failure`.

`status` is `success` only after all entries finish without failure. Any failure is `failed`, even if rollback completed. `rollback.completed` means cleanup attempts finished; it does not make the operation successful.

## Implementation boundaries

| Concern | Design constraint |
|---|---|
| CLI surface | Only `link` recognizes `--report=json`; all other commands retain current option handling. |
| Default behavior | No report option means existing stdout/stderr wording and behavior remain untouched. |
| Safety | Reuse entry-state checks, conflict refusal, repo-owned-link protection, and per-invocation rollback. |
| Rendering | Build records during execution and render only once at completion; use shell-safe JSON string escaping for every dynamic value. Do not depend on `jq`, Python, or a newly installed tool. |
| Output streams | In JSON mode, progress messages move to stderr and stdout is reserved exclusively for the final JSON document. |
| Consumer boundary | `dbootstrap` may consume the JSON contract later; this repository neither changes nor invokes it. |
| Unchanged commands | `status` and `verify` remain read-only and keep their current selection scope and output. |

## Failure and rollback details

- The implementation must retain enough per-entry state to rewrite `changed` records to `rolled_back` after a later failure.
- Parent directories are reported only when this invocation created and later removed them; pre-existing or non-empty directories are never reported as removed.
- If rollback cleanup itself cannot remove an expected link or directory, the aggregate remains `failed`, rollback metadata must expose the incomplete state, and stderr carries diagnostics.
- A link creation failure records the entry that failed. An unknown module or other selection failure records a top-level failure even if `entries` is empty.

## Test strategy

Extend the existing Bash integration/regression harness under `dotlink/tests/`; do not introduce a new test framework or runtime dependency.

Cover at minimum:

1. A successful multi-module report: one JSON document, schema version, selected-module order, deterministic entry order, and `changed` outcomes.
2. A repeated invocation: `unchanged` outcomes, `success`, and no rollback.
3. A conflict after one or more creations: nonzero exit, failed entry/cause, prior entries changed to `rolled_back`, accurate removed-target/directory metadata, and no partial-success aggregate.
4. Unknown module, invalid `--report` value, and option use on a non-link command: retained exit codes and no linking side effects.
5. Stream separation: JSON-only stdout and human diagnostics/progress on stderr.
6. Shell-sensitive source/target names where feasible in fixtures, proving valid JSON escaping.
7. Legacy link invocation and existing `status`/`verify` cases, proving their output and scope remain unchanged.

## Quality gates

The future implementation must run and pass:

```bash
make check
make test
make verify
make all
```

`make check` validates Bash syntax, `make test` runs dotlink regressions, `make verify` validates the dotfiles boundary, and `make all` is the final combined gate.
