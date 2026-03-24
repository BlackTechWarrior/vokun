# Bash completion for vokun
# Source this file or place it in /usr/share/bash-completion/completions/

_vokun() {
    local cur prev
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    local subcommands="install remove list info search get yeet find which owns update orphans cache size recent foreign explicit export import broken hook bundle sync check diff help"

    # Complete subcommand as first argument
    if [[ $COMP_CWORD -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "$subcommands" -- "$cur") )
        return
    fi

    case "${COMP_WORDS[1]}" in
        install|info)
            # Complete with available bundle names
            local bundles
            bundles="$(vokun list --names-only 2>/dev/null)"
            COMPREPLY=( $(compgen -W "$bundles" -- "$cur") )
            ;;
        remove)
            # Complete with installed bundle names
            local installed
            installed="$(vokun list --names-only 2>/dev/null)"
            COMPREPLY=( $(compgen -W "$installed" -- "$cur") )
            ;;
        hook)
            COMPREPLY=( $(compgen -W "install remove" -- "$cur") )
            ;;
        export)
            COMPREPLY=( $(compgen -W "--json" -- "$cur") )
            ;;
        import)
            COMPREPLY=( $(compgen -W "--dry" -- "$cur") )
            ;;
        help)
            COMPREPLY=( $(compgen -W "$subcommands" -- "$cur") )
            ;;
    esac
}

complete -F _vokun vokun
