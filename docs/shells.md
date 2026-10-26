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
