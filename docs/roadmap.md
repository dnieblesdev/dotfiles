# Roadmap

This roadmap tracks active and deferred work. It is not stable policy; when a decision becomes durable, move it to `docs/decisions/` or the relevant authority doc.

## Active focus

| Area | Direction | Authority boundary |
|------|-----------|--------------------|
| Source-of-truth docs | Keep README short and move stable authority into focused docs. | `docs/vision.md` and `docs/bootstrap-contract.md` win over README summaries. |
| Dotlink lifecycle | Keep link, status, verify, and unlink behavior bounded to repo-owned symlinks. | `bin/dotlink` and `dotlink/` own local executable behavior. |
| Bootstrap split | Keep package, runtime, and OS provisioning outside this repository. | `docs/bootstrapper-handoff.md` defines the external sibling boundary. |

## Deferred work

- External sibling bootstrapper implementation, if needed.
- Broader shell test harness if dotlink behavior expands beyond current shell fixtures.
- Additional ADRs only when a decision is durable enough to outlive roadmap churn.

## Not roadmap-owned

The roadmap must not redefine bootstrap policy or project boundaries. Link to the authority doc instead:

- [`bootstrap-contract.md`](bootstrap-contract.md) for local dotfiles/bootstrap boundary.
- [`vision.md`](vision.md) for scope and non-goals.
- [`bootstrapper-handoff.md`](bootstrapper-handoff.md) for the external bootstrapper boundary.
