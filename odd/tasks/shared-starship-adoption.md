# Shared Starship and live Zsh adoption
Use Starship in Bash and Zsh with minimal environment-compatible changes; Fish stays unchanged.
Branch: `feat/shared-starship-adoption`. Local work-unit commits only; no publication authorized. Checks: focused shell tests, `make all`, live login/non-login sessions. Forecast: 180–300 authored lines; strategy: ask-on-risk.

## Specs
S1. "si, adoptemos starship en ambas hay que dar el siguiente paso y dejar todo bien."
S2. "ya sabes cambios minimos por ahora. y el scoope es pensado en que pueda funciona tanto en un ambiente general como si ya vienen scripts del entorno como nos paso con cachyOS."
S3. "fish ya lo dejamos con lo que trae CachyOS por ahora, no me quiero meter con eso."
S4. "vamos a terminar la adopcion de zsh y con eso cerrariamos la fase de shells creo yo."

## Tasks
T1 | S1–S3 | delegated (context backstop): minimal Bash Starship integration, isolated RED/GREEN and environment/reload regression tests, concise docs | done | commit: pending; RED/GREEN, tool tests 8, Zsh integrations 5 and make all PASS
T2 | S1–S3 | parent: assessment and applicable checks; commit coherent source unit | in_progress | commit: pending
T3 | S1–S4 | parent: verify drift, private backups, shared config link and reversible live Zsh adoption; real Bash/Zsh checks, preserve Fish/default shell and profile; record rollback/evidence | pending | commit: pending

## Log
L1. User request: "si, adoptemos starship en ambas hay que dar el siguiente paso y dejar todo bien. ya sabes cambios minimos por ahora. y el scoope es pensado en que pueda funciona tanto en un ambiente general como si ya vienen scripts del entorno como nos paso con cachyOS."
L2. Earlier request: "vamos a terminar la adopcion de zsh y con eso cerrariamos la fase de shells creo yo." Prompt decision: "me gustaria pasarme a Starship pero principalmente por su portabilidad a otras shells como bash asi podemos tener ambas shells (bash y zsh) con un solo gestor de prompts. fish ya lo dejamos con lo que trae CachyOS por ahora, no me quiero meter con eso. que te parece ?"
L3. Starting point: clean master `5dc78bed968da9e10533de67c4d446302c62b409`. Bash already linked with private backup `~/.local/state/dotfiles-adoption/bash.am6t0ri_`; preserve `.bash_profile`. Real `.zshrc` remains CachyOS-owned regular file. Starship, Zsh, fzf, mise, zoxide and optional system plugins installed. No packages/installers needed. No real `.zshenv`, `.zprofile`, `.zlogin`, `.p10k.zsh` observed. No user `~/.config/starship.toml` exists. `dotlink status bash zsh` returns 1 as expected: Bash linked, Zsh conflicts until original rc is safely backed up/moved. No new GitHub authorization inferred from prior mission.
L4. Read-only map: Zsh already defaults to optional Starship and detects preexisting Starship/P10k; Bash currently sets native PS1 once. Reuse existing config `config/.config/starship.toml` unchanged. Do not link the whole config module merely for Starship (unrelated deployment). Avoid `.zshenv`: interactive initialization belongs in rc. Preserve existing foreign prompt hooks rather than unsetting them. Live changes are not resumable from Git diff alone, so track backup/adoption separately. Source implementation delegated due runtime context-backstop signal, not file count.
