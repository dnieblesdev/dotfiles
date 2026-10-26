# User-owned, portable Fish preferences; no prompt or distribution configuration.
# Reuse an existing zoxide integration instead of initializing it twice.
if command -q zoxide; and not functions -q __zoxide_z
    zoxide init fish | source
end

# Re-activate once at the first prompt so later startup PATH edits cannot win.
if status is-interactive; and not set -q __dotfiles_mise_activated; and not functions -q __dotfiles_mise_activate_on_prompt
    function __dotfiles_mise_activate_on_prompt --on-event fish_prompt
        functions --erase __dotfiles_mise_activate_on_prompt
        if not command -q mise
            return
        end
        set -gx MISE_ACTIVATE_AGGRESSIVE true
        command mise activate fish | source
        set -l activation_status $pipestatus
        if test "$activation_status[1]" -eq 0; and test "$activation_status[2]" -eq 0
            set -g __dotfiles_mise_activated 1
        end
    end
end
