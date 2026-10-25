# User-owned, portable Fish preferences; no prompt or distribution configuration.
# Reuse an existing zoxide integration instead of initializing it twice.
if command -q zoxide; and not functions -q __zoxide_z
    zoxide init fish | source
end
