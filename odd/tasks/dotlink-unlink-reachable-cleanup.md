# Dotlink unlink reachable cleanup — issue #31
Objective: let `unlink` remove every repository-owned symlink it can prove it owns, on branch `fix/31-unlink-repo-owned-symlinks`; baseline `6236b0f`.
Delivery: single PR closing #31, no state file; runner: isolated public `bin/dotlink` fixtures and `make all`.

## Specs
S1. Issue authorization (verbatim): "si, y hagamos la pr de una vez. osea creas la issue implementamos la solucion, commit, pr, merge y sincronizacion. se hace la review si se necesita o es recomendable hacerlo. amosleee". Scope is the three defects recorded in [#31](https://github.com/dnieblesdev/dotfiles/issues/31).
S2. Defect 1 (verbatim from #31): "`unlink` cannot remove a symlink whose source disappeared". Source validation is required to create links, never to destroy them; ownership alone authorizes removal.
S3. Defect 2 (verbatim from #31): "A known module with no entries exits 0 in silence". `status` and `verify` must not report success for a selected known module resolving to zero entries.
S4. Defect 3 (verbatim from #31): "Removing the configuration strands symlinks invisibly". A repository-owned symlink no selected module accounts for is removed by `unlink` or reported, never silently ignored.
S5. Constraints (verbatim from #31): "`status` and `verify` stay read-only"; no new state file; configuration validation stays atomic with no fallback; foreign files, foreign symlinks and unproven broken symlinks are never touched; no change to how link creates entries or to legacy discovery conventions.
S6. Delivery: public-interface tests through `bin/dotlink` in isolated HOME/XDG fixtures with exact exit/stdout/stderr; run `make all`, `git diff --check` and one differential against `6236b0f`; commit, PR closing #31, merge and sync; native review per the user's switch and candidate consent.

## Tasks
T1 | S1-S5 | parent explore and reproduce | done | three defects reproduced on master `6236b0f` in isolated fixtures; issue #31 created with exact commands and outputs.
T2 | S2-S6 | parent inline test-first fix | pending | RED per defect, then minimal implementation, then focused GREEN.
T3 | S2-S6 | parent checks and differential | pending | `make all`, `git diff --check`, base-versus-new differential on shared commands.
T4 | S1-S6 | parent delivery | pending | commit, push, PR closing #31, merge, sync master; native review per switch.

## Log
L1. Latest request (verbatim): "si, y hagamos la pr de una vez. osea creas la issue implementamos la solucion, commit, pr, merge y sincronizacion. se hace la review si se necesita o es recomendable hacerlo. amosleee".

L2. Reproduction on `master` at `6236b0f`, isolated fixtures. Defect 1: `link agents` then `mv agents/skills` leaves the symlink; `unlink agents` exits 1 with `dotlink: …/dotlink/modules.conf:3: agents: invalid source` and the symlink survives. Defect 2: with no configuration, `link`/`status`/`verify`/`unlink agents` all exit 0, `status` and `verify` print nothing, nothing is linked. Defect 3: `link agents`, then `rm dotlink/modules.conf`; global `unlink` and `unlink agents` both exit 0 printing nothing, the functional repository-owned symlink survives, and global `verify` does not mention `agents`.

L3. Investigated the design space and rejected a state file. `is_owned_symlink` already derives ownership from the filesystem (target resolves inside `REPO_ROOT`) and `collect_module_entries` already derives intent from `modules.conf` plus legacy conventions. A separate state file would be a third copy of the truth, able to contradict both, and would force the read-only commands to write. Recorded in the issue constraints.
