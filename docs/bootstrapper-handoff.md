# External Bootstrapper Handoff

This repository does not implement machine bootstrap anymore. A future sibling bootstrapper may own software installation, runtime installation, Homebrew setup, package-manager behavior, and OS provisioning.

## Boundary

| Area | Owner |
|------|-------|
| Dotfiles modules | This repository |
| Declarative profile manifests | This repository |
| Symlink lifecycle with `bin/dotlink` | This repository |
| Packages, runtimes, Homebrew, OS setup | External sibling bootstrapper |
| Go/TUI bootstrap-controller behavior | Removed here; recover from history only if migrating externally |

## Recovery guidance

Removed bootstrap code is intentionally recoverable through normal git history. If a sibling bootstrapper needs previous behavior, recover it into a separate repository instead of reintroducing bootstrap authority here.

## Non-goals

- No compatibility shim for removed installer paths.
- No local package or runtime installation.
- No sibling bootstrapper implementation in this repository.
