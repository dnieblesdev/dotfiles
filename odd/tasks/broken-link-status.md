# Broken-link status and Bash migration
Separate the status fix from the in-progress Bash migration and deliver it first.

## Specs
S1. “modules.conf no es una fuente de estado”
S2. “drift    orphan    ~/.bashrc”
S3. “creamos la issue, subimos la pr, la mergeamos, cerramos issue. traemos esos cambios y seguimos modificando la migracion con los cambios que hicimos”

## Tasks
- T1 [S1-S2] Create approved issue and isolate fix from existing migration | parent | done: issue #33, worktree fix/33-explicit-broken-link-status
- T2 [S1-S2] Implement and verify broken-link status fix | worker | done: make all and independent verification passed; ShellCheck reports seven baseline findings and no new findings; commit: 27debbd
- T3 [S3] Review, commit, deliver and merge fix PR | parent | done: PR #34 merged 73ba0ff, issue #33 closed; fix commit 27debbd
- T4 [S3] Synchronize and resume preserved Bash migration | parent | in progress; commit: pending

## Log
L1. “oh, entiendo entonces es algo que debemos corregir. lo metemos en un commit en la misma pr, aunque yo creo que deberiamos tratar esto en una pr aparte basada en master sin otros cambios, hacemos la pr, creamos la issue, subimos la pr, la mergeamos, cerramos issue. traemos esos cambios y seguimos modificando la migracion con los cambios que hicimos”
L2. User approved current gh session, `status:approved`, `type:bug` label creation and private temporary directory under `/tmp`.
