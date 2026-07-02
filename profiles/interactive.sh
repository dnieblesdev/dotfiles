# Declarative shell-data profile. This file selects dotfiles modules only.
# Note: env/ is sourced by .bashrc and is not managed by dotlink (it contains non-hidden files).
DOTLINK_PROFILE_NAME="Interactive"
DOTLINK_PROFILE_DESCRIPTION="Interactive shell and terminal configuration"
DOTLINK_PROFILE_MODULES=(bash git zsh config)
