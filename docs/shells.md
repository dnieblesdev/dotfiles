# Bash and Zsh startup

Dotlink owns only `~/.bashrc` and `~/.zshrc` for these modules. It does not merge
existing files, replace distribution configuration, or change the login shell.

## Effective configuration audit

Read-only inventory on 2026-10-26, before implementation:

| Surface | Observed content | Relationship to this repository |
|---|---|---|
| User `.bash_profile` | Sources `.bashrc` when present | External; not managed |
| User `.bashrc` | Interactive guard, ls/grep aliases, basic PS1 | Regular file; dotlink conflict; does not source repository |
| User `.zshrc` | Sources `/usr/share/cachyos-zsh-config/cachyos-config.zsh` | Regular file; dotlink conflict; does not source repository |
| CachyOS Zsh configuration | Oh My Zsh, Powerlevel10k, git/fzf/extract plugins, highlighting, suggestions, history search, command-not-found; optional `.p10k.zsh` | Distribution/user configuration; not part of repository module |
| `/etc/profile` | System PATH and readable `/etc/profile.d/*.sh`; interactive Bash system rc | External system startup |
| `/etc/bash.bashrc` | Interactive guard and optional Bash completion | External system startup |
| `/etc/zsh/zprofile` | Sources `/etc/profile` | External system login layer |

No mise, zoxide or Starship initialization was found in those inspected startup
chains. This is static evidence, not a claim about inherited environment,
terminal invocation, or commands run manually in an existing shell. Histories,
credentials and unrelated personal files were not inspected. External startup
files were not executed or changed.

## Dependency map

```text
bash/.bashrc
  bash/{config,prompt,aliases,completions,functions}
  env/paths -> env/path.sh, optional Cargo, env/go
  env/nvm -> optional user NVM
  wsl/{env,functions} OR linux/{env,functions}
  optional mise

zsh/.zshrc
  env/paths -> env/path.sh, optional Cargo, env/go
  env/nvm -> optional user NVM
  wsl/env OR linux/env
  zsh/{completions,aliases,functions,tools}
  optional Homebrew, Bun, Starship, zoxide, mise
```

The non-hidden fragments are repository dependencies, not separate dotlink
links. The `config` module may separately provide Starship configuration; linking
`zsh` alone does not link it. Repository Zsh deliberately does not source CachyOS
or Oh My Zsh.

## Portable environment

The entrypoints resolve their symlink targets, so the checkout need not be named
`~/.dotfiles` (Bash uses GNU `readlink -f`, available on target Linux/WSL).
`DOTFILES_ROOT` identifies that checkout for shared fragments. Direct standalone
use of `env/paths` or `env/go` may supply `DOTFILES_ROOT`; their legacy fallback
remains `~/.dotfiles`.

Machine settings are opt-in: export `WORKSPACE`, `JAVA_HOME`, `FLUTTER_HOME`,
`ANDROID_HOME` or `ANDROID_SDK_ROOT` before loading the rc. Tool directories are
added only if present. Neither Linux nor WSL assigns a personal mount path.
Cargo and NVM remain optional user-owned integrations. Bash and Zsh load NVM
only when its function is not already present, so re-sourcing the rc does not
re-run NVM initialization. The completion guard checks NVM's generated `__nvm`
function; this implementation detail is tested with a synthetic fixture.

When an existing mise hook is present, the rc runs `eval "$(command mise
deactivate)"` before repository PATH changes, then activates again afterward.
This supported CLI form captures the executable's shell code and evaluates it
in the current shell; `command` bypasses any mise shell function so the code is
not merely printed. Hook presence, not an inherited `MISE_SHELL` marker alone,
proves prior activation. The official activation snippet removes/replaces its own mise hooks
before registering them, so activation calls can repeat without duplicating those
hooks. All repository
PATH changes, including Zsh's local bin and Bun, precede mise activation; mise
then restores project-selected executables ahead of competitors without
aggressive activation. Bash and Zsh guard zoxide initialization by checking for
the generated `__zoxide_z` function. That name is an implementation detail of
zoxide 0.10.0, not a stable public API; recheck the guard when upgrading. Zsh
also avoids reinitializing Starship when its generated prompt hook is present.
Reloading preserves existing prompt hooks; Bash retains a prompt selected after
its first dotfiles initialization. mise, zoxide, and Starship remain optional.
Real NVM was not available for verification; a synthetic fixture verifies its
reload behavior and PATH interaction.

Zsh discovers Homebrew
only on PATH and respects `BUN_INSTALL` (default `~/.bun`) for Bun completion and
its optional bin directory. No software is installed. Standard Linux utilities
and shell completion libraries remain system dependencies; aliases such as
`alert` require their tool (`notify-send`) only when invoked.

### Zsh history and editing

Interactive repository Zsh keeps a valid caller-provided `HISTFILE`, including
existing records; explicitly setting it to `/dev/null` remains a disk-history
opt-out. An unset, empty, or unusable destination (including a directory) falls
back to `$HOME/.zsh_history` when that path is usable, otherwise `/dev/null`; no
missing parent directories are created and invalid destinations are not
replaced. The initial `HISTSIZE` and `SAVEHIST` are 10,000. Caller limits are
never reduced for file destinations. The `/dev/null` opt-out disables disk
saving with `SAVEHIST=0`. When an existing file leaves fewer than 10,000 spare records under
`SAVEHIST`, both limits are raised to at least its observed record count plus
10,000 entries of headroom. History uses native `INC_APPEND_HISTORY` (not the
mutually exclusive timed variant) without
`SHARE_HISTORY`, so commands append incrementally but are not automatically
exchanged live across concurrent shells. Adjacent duplicates are ignored,
while older non-adjacent matches are retained; inherited options that prune all
duplicates or delete duplicates on save/expiry are disabled. History is still
bounded by the active `HISTSIZE`/`SAVEHIST` limits; a session that exceeds its
configured in-memory capacity can eventually lose older entries. Space-prefixed
commands are not promised to be secret or excluded.

The first repository rc load selects native ZLE Emacs mode and binds Up/Down in
the Emacs keymap to `history-beginning-search-backward` and
`history-beginning-search-forward`. These built-in ZLE widgets search history by
the current line prefix and preserve ordinary editing when no match exists. The
initialization guard deliberately does not reapply bindings on rc reload, so
user changes made after the first load survive. A keymap chosen by user config
before the first load is replaced by the documented Emacs initial default;
non-Emacs maps and bindings installed after that load are not changed. No
substring-search plugin is installed.

Run `python3 dotlink/tests/shells.py` for isolated startup regressions and
`python3 dotlink/tests/zsh-native.py` for native history and ZLE regressions;
Python 3, Bash and Zsh are test dependencies, not shell startup dependencies.

## Startup contract and verification limits

The modules guarantee behavior only when their repository rc entrypoint is loaded;
`dotlink` links `.bashrc` and `.zshrc`, not a complete login-file chain. They do
not overwrite or synthesize `.bash_profile`, `.profile`, `.zprofile`, or `.zshenv`.
A Bash user-owned profile may source `.bashrc`; without that explicit chain, a
login Bash session has no repository integration. Bash login tests use the
harness's `--noprofile` isolation and separately source a disposable profile
fixture, so they prove the opt-in chain rather than executing host `/etc/profile`.

Zsh's compiled global `zshenv` is an unavoidable earlier startup layer. Isolated
Zsh tests use `-d -f` to suppress user startup files, while the global `zshenv`
may still run. The harness sets a temporary `HOME`, `ZDOTDIR`, XDG roots and a
restricted `PATH`; it does not source the real user's or distribution's startup
files. The startup matrix explicitly loads the repository rc in each interactive,
noninteractive, login and non-login process. This distinguishes the rc's own
interactive guard from the shell's automatic startup-file policy.

| Shell/session | Repository behavior when rc is explicitly loaded | What the module does not guarantee |
|---|---|---|
| Bash interactive, login or non-login | `.bashrc` loads interactive configuration | Login startup reaches `.bashrc` only if the user-owned profile sources it |
| Bash noninteractive, login or non-login | `.bashrc` returns before repository setup | Does not override `BASH_ENV` or profile behavior owned elsewhere |
| Zsh interactive, login or non-login | `.zshrc` loads interactive configuration | Does not manage `.zshenv`, `.zprofile` or `.zlogin` |
| Zsh noninteractive, login or non-login | `.zshrc` returns before repository setup | Zsh's earlier global/user `zshenv` layers remain outside dotlink ownership |

The isolated tests check repeated loading, unchanged noninteractive PATH and
functions, and preservation of an explicitly supplied `WORKSPACE` while a
scoped `grep` wrapper simulates `/proc/version` identifying WSL. This is not
certification on an actual WSL distribution.
They test shell entrypoints and selected fixtures, not every terminal emulator,
remote-shell rule, distribution startup file, or system-level compiled Zsh
configuration. Existing user files remain untouched; test markers and fixtures
live under a temporary test HOME and are removed by test teardown.

## Bash, Zsh and Fish compared

| Capability | Bash | Zsh | Fish |
|---|---|---|---|
| Repository entrypoint ownership | `.bashrc` only | `.zshrc` only | Individual `conf.d/*.fish` snippets |
| Noninteractive behavior | Rc returns before interactive setup | Rc returns before interactive setup | Snippet does not activate mise outside interactive sessions |
| mise | Official Bash activation after repository PATH setup; no forced aggressive policy | Official Zsh activation after repository PATH setup; no forced aggressive policy | Official activation deferred to first prompt and deliberately enables aggressive activation for that session |
| zoxide | Optional; guarded against reinitialization by generated function | Optional; guarded against reinitialization by generated function | Optional; guarded against reinitialization by generated function |
| User configuration | NVM and other user-owned integrations are optional; not installed or replaced | Same; distribution Zsh frameworks are not sourced by the module | `config.fish`, universal variables and distribution settings are user-owned |
| Startup files managed | `.bashrc` | `.zshrc` | Repository-owned individual snippets, not `config.fish` |

Bash and Zsh intentionally use the standard mise activation policy. Fish's
first-prompt callback and aggressive activation are a deliberate Fish-specific
choice that corrects PATH changes made by later Fish configuration; that policy
is not copied to Bash/Zsh. NVM behavior is exercised with a synthetic user-owned
fixture; real NVM was unavailable, so real-tool coexistence is not proven. mise
and zoxide integration evidence with installed binaries is reported separately
by the tools-focused test when available.

The isolated shell suite requires Python 3, Bash, Zsh, and GNU/Linux utilities
used by the startup fragments (including GNU `readlink` and coreutils). Shells
and tools are not installed by this repository. Tests use a bounded executable
allowlist; this is not a substitute for running on each target distribution.
No HOME migration or login-file migration was applied. Residual risks include
external files changing PATH or prompts after the repository rc, compiled/global
Zsh startup behavior, and actual WSL distribution differences.

## Session boundaries

| Session | Bash | Zsh |
|---|---|---|
| Interactive non-login | `.bashrc` | `.zshenv`, then `.zshrc` |
| Interactive login | System profile; first existing `.bash_profile`, `.bash_login`, `.profile`; `.bashrc` only if sourced | `.zshenv`, `.zprofile`, `.zshrc`, `.zlogin` |
| Noninteractive non-login | Normally no `.bashrc`; `$BASH_ENV` may execute | `.zshenv`, not `.zshrc` |
| Noninteractive login | Login profile chain; repository rc returns if explicitly sourced | Environment and login files, not `.zshrc` |

Global Zsh files interleave with user files. `ZDOTDIR` can relocate user Zsh
startup files. Remote Bash has additional startup rules. Both repository rc
files return immediately when noninteractive. No login files are managed or
required by dotlink; ensuring Bash login loads `.bashrc` remains a user-owned
choice. Later external startup files may change PATH or prompts.
