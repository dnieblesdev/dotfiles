# Roadmap

This roadmap tracks active and deferred work. It is not stable policy; when a decision becomes durable, move it to `docs/decisions/` or the relevant authority doc.

## Active focus

| Area | Direction | Authority boundary |
|------|-----------|--------------------|
| Source-of-truth docs | Keep README short and move stable authority into focused docs. | `docs/vision.md` and `docs/bootstrap-contract.md` win over README summaries. |
| Bootstrap hardening | Continue improving replay, provenance, and controller boundaries without changing shell-first ownership. | `installer/install.sh` and shell libs remain canonical. |
| Optional frontend | Keep Go/TUI as an adapter over shell-owned commands. | Frontend behavior must consume `list`, `plan`, `apply`, and `controller`. |

## Deferred work

- Offline hardening for the `tui` launcher and Go runtime install path.
- Signed or provenance-aware `bootstrap-controller` build distribution.
- Dedicated shell test harness if shell bootstrap behavior starts changing frequently.
- Additional ADRs only when a decision is durable enough to outlive roadmap churn.

## Not roadmap-owned

The roadmap must not redefine bootstrap policy, privilege rules, catalog semantics, or project boundaries. Link to the authority doc instead:

- [`bootstrap-contract.md`](bootstrap-contract.md) for bootstrap behavior.
- [`vision.md`](vision.md) for scope and non-goals.
- [`installer.md`](installer.md) for operational usage.
