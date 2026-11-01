# Dotfiles Contract

This repository is canonical only for dotfiles modules, declarative profiles, and symlink lifecycle. Package installation, runtime installation, Homebrew setup, OS provisioning, and Go/TUI controller behavior belong outside this repository.

## Contract surface

| Surface | Authority |
|---------|-----------|
| `bin/dotlink link` | Create repository-owned symlinks for selected modules or profiles. |
| `bin/dotlink list` | List modules selected by a profile or explicit arguments. |
| `bin/dotlink status` | Report missing, linked, drifted, skipped, or conflicting paths without modifying files. |
| `bin/dotlink unlink` | Remove only symlinks proven to be repository-owned. |
| `bin/dotlink verify` | Fail when selected links are missing, drifted, or conflicting. |

No local command in this repository installs software, configures operating-system dependencies, or provisions a workstation.

## Removed and non-authoritative surfaces

The following surfaces are intentionally removed or non-authoritative in this repository:

- `installer/install.sh` (removed; no compatibility shim)
- `installer/dotlink` (removed; no compatibility shim)
- `cmd/bootstrap-controller/` (removed; non-authoritative)
- `internal/controller/` (removed; non-authoritative)
- `bootstrap-controller` (removed; non-authoritative)
- controller-only Go module and tests

There is no compatibility shim and no preservation guarantee for the removed installer paths.

## Dotlink safety contract

- Dotlink manages only symlinks it can prove point into this repository.
- Regular files, directories, foreign symlinks, and unproven broken symlinks are conflicts.
- `status` and `verify` are read-only drift detectors.
- Optional modules that do not apply to the current platform are reported as `skip` and do
  not fail `verify`; a linked-but-broken optional module still reports drift or conflict.
- `unlink` removes only repository-owned symlinks. Removal is authorized by ownership,
  not by the source still existing: a moved or deleted source never strands a link this
  repository owns. A repository-owned symlink that no selected module accounts for is
  reported as `drift orphan` and removed by `unlink`.
- `status` and `verify` do not report success for a selected known module that resolves to
  no entry at all; they name the module and fail. An orphaned link is reported, but it is
  not an entry: a module whose only remaining artifact is a stranded link still fails, so a
  deleted source can no longer pass as healthy.
- `link` continues after individual failures and retains successful links. It cleans only incomplete changes created for the failed entry, never earlier successes.
- Profiles are restricted shell-data manifests, not executable provisioning scripts.
- Platform-specific Git settings live in a separate module and are reached through a
  Git `[include]`, never by making the common config machine-aware. The common
  `git/.gitconfig` stays portable: no machine paths, no absolute interpreter paths,
  and no Windows-only `core` keys.

## Best-effort linking

`link` attempts every safe selected entry in deterministic order, in legacy and
explicit modes alike. A conflict or failed source/parent/link operation is reported
and does not stop later entries. Existing foreign data is never changed. Earlier
and later successes remain linked; cleanup removes only incomplete artifacts
created for the failed entry. A malformed configuration or an ambiguous selected
plan (duplicate or nested targets) is rejected before any writes.

Every executed link run ends with `dotlink: summary: created=N unchanged=N failed=N`.
Exit 0 means every entry succeeded or was already linked; exit 1 means at least
one entry failed. With `--report=json`, stdout contains only the JSON document;
progress, errors and the summary go to stderr. Ordered report entries identify
every success and failure; the top-level failure identifies the first failed
entry. The existing `rollback` metadata describes failed-entry cleanup only,
not undoing successful entries. If a base cannot be resolved, the failed entry has
an empty target and the top-level failure target is null; other safe entries still
run, including entries in the same module. Other lifecycle commands do not gain
summaries and retain their prior processing before a collection error.

## Explicit module mappings

`dotlink/modules.conf` is literal data, never executed. A missing, empty, or
comment-only file leaves every module on legacy discovery; an omitted module
also uses legacy discovery. A present invalid file is rejected, including errors
in unselected modules: there is no fallback after an error.

```ini
[module agents]
[link]
source = skills
target = .agents/skills
```

Each known `[module NAME]` appears at most once and contains one or more `[link]`
blocks. Each block requires exactly one nonempty `source` and `target`; optional
`base` is `home` or `xdg_config`, defaulting to `home` only when absent. Unknown
or duplicate fields, properties outside links, malformed headers and empty modules
are errors. `source` is relative to the module, `target` to its base. Absolute,
empty, dot or dot-dot components, repeated slashes and trailing slashes are
invalid. Sources must be real regular files or directories, with no symlink
components. Target parents must be real directories, not symlinks.

`home` uses `DOTLINK_HOME` (normally `HOME`). `xdg_config` uses a nonempty
`XDG_CONFIG_HOME`, otherwise `DOTLINK_HOME/.config`. Selected bases must be
absolute and contain no control bytes: the inventory transport uses tabs and
newlines. This also rejects delimiter-ambiguous XDG roots in legacy Fish.
XDG is validated only when selected. For explicit mappings, status and verify
stop at an invalid source without repairing it, report the source error, and report
an existing broken repository-owned destination as `drift orphan` or a conflicting
destination as `conflict`. Unlink relies on ownership even if the source is gone;
link reports an invalid source and continues.
Duplicate or nested destinations
across distinct selected mappings, whether explicit or legacy, are rejected before
writes. Repeating a module argument or profile member is not a second mapping:
link processes that module once, while list/status keep their historical selection
output. Declaring duplicate destinations inside a module remains an error, and it
is reported by the parser as `duplicate target` or `nested target` at the offending
`target` line, so every command rejects it even when that module is unselected.

Only blank lines and full-line `#` comments are ignored. Split properties at the
first `=` and trim surrounding spaces and tabs; internal spaces, `#`, `$`, `*`
and `=` are literal. There are no inline comments, quoting, escapes, multiline
values, or variable, command, or glob expansions. Control bytes and NUL are
invalid in values. LF, CRLF, and a final line without newline are supported.
The configuration must be a readable real regular file, not a symlink or directory.

`agents` is deliberately outside all profiles. Its only mapping links
`agents/skills` to `~/.agents/skills`; `.gitkeep` is a marker, not a skill.
Existing personal directories conflict and must be handled manually; dotlink
never migrates them. Root `skills/` remains repository-only. The `bash` module
explicitly maps `bash/.bashrc` to `~/.bashrc`, and `zsh` maps `zsh/.zshrc`
to `~/.zshrc`; additional Bash or Zsh destinations require their own mappings.
Other legacy modules continue using discovery until explicitly migrated.

## Fish: individual snippets

The `fish` module links only regular `*.fish` files directly inside
`fish/.config/fish/conf.d/` to `$XDG_CONFIG_HOME/fish/conf.d/`.
An empty or unset `XDG_CONFIG_HOME` falls back to `$DOTLINK_HOME/.config`
(`$HOME/.config` normally); a relative value is rejected. Before linking Fish,
`dotlink` checks every existing component from `/` through `fish/conf.d` and
rejects symbolic-link ancestors (including broken links) and non-directory
ancestors without modifying their destinations. `XDG_CONFIG_HOME` paths with
`.` or `..` components are rejected rather than normalized. Other modules retain
their existing destinations and directory-link behavior.

Select Fish explicitly with `bin/dotlink link fish`; existing profiles do not
select it. Fish is portable, not platform-optional: global `status` reports
missing snippets and global `verify` fails until they are linked, like other
non-optional modules. Existing files and foreign links remain conflicts.

`dotfiles.fish` initializes zoxide with `zoxide init fish | source` only when
its executable is available and the Fish function `__zoxide_z` is not already
defined. Without zoxide, the snippet leaves the shell unchanged. Reloading the
snippet or loading it after an existing zoxide initialization does not initialize
zoxide again when that function is present.

The duplicate-initialization guard relies on an internal function emitted by
zoxide 0.10.0, not a stable public API. Recheck it when upgrading zoxide. It does
not prevent a later snippet or `config.fish` from initializing zoxide again.

This module does not manage `config.fish`, distribution settings, universal
variables or history. In interactive shells, it schedules one named `fish_prompt`
callback that removes itself and runs the official `mise activate fish` once.
This deliberately runs official activation at the first prompt even if another
startup file activated mise earlier, so later startup PATH edits are corrected.
Immediately before that activation it sets `MISE_ACTIVATE_AGGRESSIVE=true` in
this interactive session only, allowing mise's documented aggressive activation
to restore tool PATH priority when mise updates the environment. This may override
an inherited false value in this session; it does not modify global or Fish
configuration. It does not trust an inherited `MISE_SHELL` marker; without a
`mise` executable, it silently removes the callback without activation.
Noninteractive shells are unchanged. Mise's official activation hooks handle
subsequent directory changes and project-specific tool versions; priority is
restored when mise updates the environment, not continuously against arbitrary
later PATH edits. Neighboring
snippets remain untouched. Fish runs snippets before `config.fish`; matching
snippet names can shadow vendor files. Do not reuse vendor names or source
distribution configuration here.

The first-prompt activation cannot protect commands executed earlier by
`config.fish`, nor can it guarantee PATH priority against arbitrary later PATH
edits until mise next updates the environment. It does not configure global
aggressive activation.

Use the same XDG destination for link, status, verify and unlink. The existing
orphan scan covers `DOTLINK_HOME`, not external XDG trees: removing a source
snippet outside that tree may leave a broken link requiring manual inspection.

## Platform layers

The repository separates portable configuration from platform overrides without
branching inside dotlink, which is platform-agnostic by design.

| Layer | Path | Reached by |
|-------|------|------------|
| Portable Git config | `git/.gitconfig` | `base` and `interactive` profiles |
| Windows Git overrides | `git-win/.gitconfig.win` | Explicit `bin/dotlink link git-win` |

The common config includes `~/.gitconfig.win` through `[include]`. An absent include
is silently ignored by Git, so WSL and native Linux run on the portable values alone
and no profile has to select `git-win`.

## Recovery / Troubleshooting

When `status` or `verify` reports conflicts, drift, or missing links:

1. **Inspect the state** without modifying files:
   ```bash
   bin/dotlink status --profile base
   ```
2. **Identify the conflict type** for each reported path:
   - `conflict` — the path is a regular file, directory, foreign symlink, or broken symlink not owned by the repository.
   - `drift` — the path is a repository-owned symlink pointing at a different module or commit.
   - `missing` — the path does not exist.
3. **Resolve manually** before re-running `link`:
   - Back up the conflicting file or directory, then remove it.
   - For a foreign symlink that should not be managed, leave it in place and exclude the module from the profile.
   - For a drifted owned symlink, remove it and let `link` recreate it.
4. **Re-run link and verify**:
   ```bash
   bin/dotlink link --profile base
   bin/dotlink verify --profile base
   ```

If a previous `link` operation was interrupted, run `status` to see whether any partially-created symlinks remain; `unlink` removes only repository-owned symlinks.

## Related docs

- Use [`shells.md`](shells.md) for Bash/Zsh startup ownership, isolated verification, and the Bash/Zsh/Fish comparison.
- Use [`vision.md`](vision.md) for project boundaries.
- Use [`decisions/adr-0002-dotfiles-only-boundary.md`](decisions/adr-0002-dotfiles-only-boundary.md) for the durable ownership decision.
