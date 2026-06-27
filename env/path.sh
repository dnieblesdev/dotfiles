# Portable PATH helpers for Bash and Zsh.

if [ -n "${ZSH_VERSION-}" ]; then
    path_remove() {
        [ -n "$1" ] || return 0

        local -a newpath
        local entry

        for entry in $path; do
            [ "$entry" = "$1" ] && continue
            newpath+=("$entry")
        done

        path=("${newpath[@]}")
    }

    path_prepend() {
        [ -n "$1" ] || return 0

        path_remove "$1"
        path=("$1" "${path[@]}")
    }

    path_append() {
        [ -n "$1" ] || return 0

        path_remove "$1"
        path+=("$1")
    }
else
    path_remove() {
        [ -n "$1" ] || return 0

        case ":${PATH}:" in
            *":$1:"*) ;;
            *) return 0 ;;
        esac

        old_ifs=$IFS
        old_path=$PATH
        IFS=:
        PATH=

        for entry in $old_path; do
            [ "$entry" = "$1" ] && continue

            if [ -n "$PATH" ]; then
                PATH="$PATH:$entry"
            else
                PATH="$entry"
            fi
        done

        IFS=$old_ifs
        export PATH
    }

    path_prepend() {
        [ -n "$1" ] || return 0

        path_remove "$1"

        if [ -n "$PATH" ]; then
            PATH="$1:$PATH"
        else
            PATH="$1"
        fi
        export PATH
    }

    path_append() {
        [ -n "$1" ] || return 0

        path_remove "$1"

        if [ -n "$PATH" ]; then
            PATH="$PATH:$1"
        else
            PATH="$1"
        fi
        export PATH
    }
fi
