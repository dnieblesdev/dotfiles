# Project Source of Truth

The repository is dotfiles-only. Its authority is limited to configuration modules, declarative profiles, and symlink lifecycle behavior.

## Authority

- This repository is the source of truth for dotfiles behavior only.
- `bin/dotlink` and the `dotlink/` implementation own linking, listing, status, unlinking, and verification.
- Declarative profile manifests define module selection and remain non-bootstrap.
- Sibling bootstrapper work belongs to a separate repository boundary and is not authoritative here.

## Non-goals

- No legacy installer compatibility shim is required for `installer/install.sh` or `installer/dotlink`.
- No `cmd/bootstrap-controller/`, `internal/controller/`, `bootstrap-controller`, or controller-only Go/TUI artifacts are authoritative for this repository.
- No OS bootstrap, package installation, or runtime provisioning belongs in this repo.

## Scope

The active contract covers dotfiles-only module selection, profile manifests, and symlink ownership/safety rules.
