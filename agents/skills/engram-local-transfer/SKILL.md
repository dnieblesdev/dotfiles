---
name: engram-local-transfer
description: "Trigger: import Engram memories from a Windows partition mounted on Linux, migrate local Engram data without cloud. Safely transfer Windows Engram records into Linux."
license: Apache-2.0
metadata:
  author: dniebles
  version: "1.0"
---

## Activation Contract

Use only from Linux to transfer a local Engram store from a mounted Windows partition into Linux, without cloud. Do not instruct the user to run this workflow from Windows. Do not use for ordinary searches or cloud sync.

## Hard Rules

- Keep data local; never upload, disclose records, or commit exports.
- Confirm source, destination, and project scope. Treat export files as sensitive.
- Preserve the source. Never replace an active store or copy only `engram.db`.
- Never infer Windows shutdown/hibernation state from Linux or from a mounted partition. Require the user to confirm a full shutdown (not sleep, hibernate, or hybrid shutdown); Linux checks only establish local process and mount status.
- Use native `export`/`import`; back up the destination first. Never delete source, backup, or export without explicit request.
- Stop clients using a store before importing; restart and verify afterward.

## Decision Gates

| Situation | Action |
| --- | --- |
| Scope unclear | Ask whether to export all projects or a selected project. |
| Windows source is mounted in Linux | Ask the user to confirm a full shutdown, not sleep/hibernate/hybrid shutdown. If confirmed and no Linux Engram process uses it, stage the complete `.engram` directory locally, then export from the copy. |
| Shutdown or hibernation state is unknown | Do not access the Windows store; ask the user to fully shut down Windows, then resume this workflow from Linux. |
| CLI compatibility or import behavior uncertain | Test on an isolated copy first. |
| Destination has data | Back it up, then merge; never silently replace. |
| No local transfer route | Ask the user to choose one; don't fall back to cloud. |

## Execution Steps

1. Check `engram --help`, `engram export --help`, `engram import --help`, and the CLI version.
2. For a mounted Windows volume, ask the user to confirm Windows was fully shut down—not slept, hibernated, or hybrid-shut down. Linux cannot prove Windows' power state; process checks cover Linux only. If the user cannot confirm, stop. Otherwise copy the complete `.engram` directory (including database and WAL) to new Linux-local staging; never write to the Windows volume. Export from that copy with `ENGRAM_DATA_DIR=<staging-copy> engram export <linux-file> --all` or `--project <name>`. Leave the original untouched.
3. Back up destination using SQLite `.backup` or an equivalent supported method; verify `PRAGMA integrity_check`.
4. Stop destination clients/server, run `ENGRAM_DATA_DIR=<destination> engram import <file>`, then restart Engram.
5. Verify integrity, before/after counts, and a user-selected search. Report limits of the exported data.

## Output Contract

Report paths, scope, backup/export, import result, integrity/count checks, service status, and unresolved issues. Don't claim success until checks pass.

## References

Use the installed Engram CLI help; options and behavior vary by version.
