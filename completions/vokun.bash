# Bash completion for vokun
# Source this file or place it in /usr/share/bash-completion/completions/

_vokun() {
    local cur prev
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    local subcommands="install remove select list info search get yeet find which owns update orphans cache size recent foreign explicit export import broken history hook setup uninstall bundle sync check diff profile log rollback dotfiles status why snapshot untracked doctor help"

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
                COMPREPLY=( $(compgen -W "--dry-run --yes --untrack --all" -- "$cur") )
            else
                local installed
                installed="$(vokun list --names-only 2>/dev/null)"
                COMPREPLY=( $(compgen -W "$installed" -- "$cur") )
            fi
            ;;
        select)
            local installed
            installed="$(vokun list --names-only 2>/dev/null)"
            COMPREPLY=( $(compgen -W "$installed" -- "$cur") )
            ;;
        hook)
            COMPREPLY=( $(compgen -W "install remove" -- "$cur") )
            ;;
        profile)
            COMPREPLY=( $(compgen -W "list switch create delete copy show" -- "$cur") )
            ;;
        sync)
            if [[ "$cur" == --* ]]; then
                COMPREPLY=( $(compgen -W "--auto --quiet" -- "$cur") )
            fi
            ;;
        bundle)
            if [[ "$cur" == --* ]]; then
                COMPREPLY=( $(compgen -W "--editor" -- "$cur") )
            else
                COMPREPLY=( $(compgen -W "create add rm edit delete" -- "$cur") )
            fi
            ;;
        get)
            if [[ "$cur" == --* ]]; then
                COMPREPLY=( $(compgen -W "--overwrite" -- "$cur") )
            fi
            ;;
        yeet)
            if [[ "$cur" == --* ]]; then
                COMPREPLY=( $(compgen -W "--untrack" -- "$cur") )
            fi
            ;;
        cache)
            COMPREPLY=( $(compgen -W "--clean --purge" -- "$cur") )
            ;;
        size)
            COMPREPLY=( $(compgen -W "--top" -- "$cur") )
            ;;
        recent)
            COMPREPLY=( $(compgen -W "--count" -- "$cur") )
            ;;
        export)
            COMPREPLY=( $(compgen -W "--json --profile --all" -- "$cur") )
            ;;
        import)
            COMPREPLY=( $(compgen -W "--dry" -- "$cur") )
            ;;
        log)
            if [[ "$cur" == --* ]]; then
                COMPREPLY=( $(compgen -W "--count" -- "$cur") )
            fi
            ;;
        dotfiles)
            COMPREPLY=( $(compgen -W "init apply push pull status edit" -- "$cur") )
            ;;
        snapshot)
            if [[ $COMP_CWORD -eq 2 ]]; then
                COMPREPLY=( $(compgen -W "create list diff restore delete" -- "$cur") )
            elif [[ "$cur" == --* ]]; then
                COMPREPLY=( $(compgen -W "--dry-run --yes" -- "$cur") )
            else
                # Complete snapshot names for diff/restore/delete
                local snapshots_dir="${XDG_CONFIG_HOME:-$HOME/.config}/vokun/snapshots"
                if [[ -d "$snapshots_dir" ]]; then
                    local names
                    names="$(ls "$snapshots_dir" 2>/dev/null)"
                    COMPREPLY=( $(compgen -W "$names" -- "$cur") )
                fi
            fi
            ;;
        find)
            COMPREPLY=( $(compgen -W "--aur --pick" -- "$cur") )
            ;;
        which)
            COMPREPLY=( $(compgen -W "--remote" -- "$cur") )
            ;;
        update)
            COMPREPLY=( $(compgen -W "--aur --aur-only --check" -- "$cur") )
            ;;
        orphans)
            COMPREPLY=( $(compgen -W "--clean --deep" -- "$cur") )
            ;;
        list)
            COMPREPLY=( $(compgen -W "--installed --deps" -- "$cur") )
            ;;
        history)
            COMPREPLY=( $(compgen -W "--installed --removed --upgraded --downgraded --search --count" -- "$cur") )
            ;;
        why|untracked|doctor)
            ;;
        help)
            COMPREPLY=( $(compgen -W "$subcommands" -- "$cur") )
            ;;
    esac
}

complete -F _vokun vokun
