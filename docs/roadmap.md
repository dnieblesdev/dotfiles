# Roadmap

This roadmap tracks active and deferred work. It is not stable policy; when a decision becomes durable, move it to `docs/decisions/` or the relevant authority doc.

## Active focus

| Area | Direction | Authority boundary |
|------|-----------|--------------------|
| Repository organization | Move toward a clearer `modules/`-first layout so linkable dotfiles are grouped separately from profiles and the dotlink engine. Treat this as immediate architecture work, not cosmetic cleanup. | `bin/dotlink`, `dotlink/`, `profiles/`, module manifests, tests, and docs must migrate together so symlink behavior remains unchanged. |
| Source-of-truth docs | Keep README short and move stable authority into focused docs. | `docs/vision.md` and `docs/dotfiles-contract.md` win over README summaries. |
| Dotlink lifecycle | Keep link, status, verify, and unlink behavior bounded to repo-owned symlinks. | `bin/dotlink` and `dotlink/` own local executable behavior. |

## Deferred work

- Broader shell test harness if dotlink behavior expands beyond current shell fixtures.
- Additional ADRs only when a decision is durable enough to outlive roadmap churn.

## Not roadmap-owned

The roadmap must not redefine project boundaries. Link to the authority doc instead:

- [`dotfiles-contract.md`](dotfiles-contract.md) for the local dotfiles contract.
- [`vision.md`](vision.md) for scope and non-goals.
