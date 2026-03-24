# Bash completion for vokun
# Source this file or place it in /usr/share/bash-completion/completions/

_vokun() {
    local cur prev
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    local subcommands="install remove list info search get yeet find which owns update orphans cache size recent foreign explicit export import broken hook setup uninstall bundle sync check diff profile help"

    # Complete subcommand as first argument
    if [[ $COMP_CWORD -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "$subcommands" -- "$cur") )
        return
    fi

    case "${COMP_WORDS[1]}" in
        install)
            if [[ "$cur" == --* ]]; then
                COMPREPLY=( $(compgen -W "--pick --exclude --only --dry-run --yes" -- "$cur") )
            else
                local bundles
                bundles="$(vokun list --names-only 2>/dev/null)"
                COMPREPLY=( $(compgen -W "$bundles" -- "$cur") )
            fi
            ;;
        info)
            local bundles
            bundles="$(vokun list --names-only 2>/dev/null)"
            COMPREPLY=( $(compgen -W "$bundles" -- "$cur") )
            ;;
        remove)
            if [[ "$cur" == --* ]]; then
                COMPREPLY=( $(compgen -W "--dry-run --yes" -- "$cur") )
            else
                local installed
                installed="$(vokun list --names-only 2>/dev/null)"
                COMPREPLY=( $(compgen -W "$installed" -- "$cur") )
            fi
            ;;
        hook)
            COMPREPLY=( $(compgen -W "install remove" -- "$cur") )
            ;;
        profile)
            COMPREPLY=( $(compgen -W "list switch create delete show" -- "$cur") )
            ;;
        sync)
            if [[ "$cur" == --* ]]; then
                COMPREPLY=( $(compgen -W "--auto --quiet" -- "$cur") )
            fi
            ;;
        bundle)
            COMPREPLY=( $(compgen -W "create add rm edit delete" -- "$cur") )
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
