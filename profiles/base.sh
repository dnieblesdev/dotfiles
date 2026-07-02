# Declarative shell-data profile. This file selects dotfiles modules only.
# Note: env/ is sourced by .bashrc and is not managed by dotlink (it contains non-hidden files).
DOTLINK_PROFILE_NAME="Base"
DOTLINK_PROFILE_DESCRIPTION="Base shell, Git, and environment dotfiles"
DOTLINK_PROFILE_MODULES=(bash git)
