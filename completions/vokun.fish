# Fish completion for vokun
# Place this file in ~/.config/fish/completions/ or /usr/share/fish/vendor_completions.d/

# Disable file completions by default
complete -c vokun -f

# Subcommands
set -l subcommands install remove list info search get yeet find which owns update orphans cache size recent foreign explicit export import broken hook help

complete -c vokun -n "not __fish_seen_subcommand_from $subcommands" -a install  -d "Install a bundle"
complete -c vokun -n "not __fish_seen_subcommand_from $subcommands" -a remove   -d "Remove a bundle"
complete -c vokun -n "not __fish_seen_subcommand_from $subcommands" -a list     -d "List bundles"
complete -c vokun -n "not __fish_seen_subcommand_from $subcommands" -a info     -d "Show bundle info"
complete -c vokun -n "not __fish_seen_subcommand_from $subcommands" -a search   -d "Search for packages"
complete -c vokun -n "not __fish_seen_subcommand_from $subcommands" -a get      -d "Get a package"
complete -c vokun -n "not __fish_seen_subcommand_from $subcommands" -a yeet     -d "Remove a package"
complete -c vokun -n "not __fish_seen_subcommand_from $subcommands" -a find     -d "Find a package"
complete -c vokun -n "not __fish_seen_subcommand_from $subcommands" -a which    -d "Which bundle owns a package"
complete -c vokun -n "not __fish_seen_subcommand_from $subcommands" -a owns     -d "Show package owner"
complete -c vokun -n "not __fish_seen_subcommand_from $subcommands" -a update   -d "Update packages"
complete -c vokun -n "not __fish_seen_subcommand_from $subcommands" -a orphans  -d "List orphaned packages"
complete -c vokun -n "not __fish_seen_subcommand_from $subcommands" -a cache    -d "Manage package cache"
complete -c vokun -n "not __fish_seen_subcommand_from $subcommands" -a size     -d "Show package sizes"
complete -c vokun -n "not __fish_seen_subcommand_from $subcommands" -a recent   -d "Show recently installed"
complete -c vokun -n "not __fish_seen_subcommand_from $subcommands" -a foreign  -d "List foreign packages"
complete -c vokun -n "not __fish_seen_subcommand_from $subcommands" -a explicit -d "List explicitly installed"
complete -c vokun -n "not __fish_seen_subcommand_from $subcommands" -a export   -d "Export custom bundles and config"
complete -c vokun -n "not __fish_seen_subcommand_from $subcommands" -a import   -d "Import bundles from a file"
complete -c vokun -n "not __fish_seen_subcommand_from $subcommands" -a broken   -d "Check for broken symlinks and deps"
complete -c vokun -n "not __fish_seen_subcommand_from $subcommands" -a hook     -d "Manage pacman notification hook"
complete -c vokun -n "not __fish_seen_subcommand_from $subcommands" -a help     -d "Show help"

# Global flags
complete -c vokun -l yes -s y     -d "Skip confirmation prompts"
complete -c vokun -l no-color     -d "Disable colored output"
complete -c vokun -l version -s v -d "Show version"

# Subcommand arguments: install completes with bundle names and flags
complete -c vokun -n "__fish_seen_subcommand_from install" -a "(vokun list --names-only 2>/dev/null)" -d "Bundle"
complete -c vokun -n "__fish_seen_subcommand_from install" -l pick     -d "Interactively select packages"
complete -c vokun -n "__fish_seen_subcommand_from install" -l exclude  -d "Skip specific packages (comma-separated)"
complete -c vokun -n "__fish_seen_subcommand_from install" -l only     -d "Install only these packages (comma-separated)"
complete -c vokun -n "__fish_seen_subcommand_from install" -l dry-run  -d "Preview without installing"

# info completes with bundle names
complete -c vokun -n "__fish_seen_subcommand_from info"    -a "(vokun list --names-only 2>/dev/null)" -d "Bundle"

# remove completes with installed bundle names and flags
complete -c vokun -n "__fish_seen_subcommand_from remove"  -a "(vokun list --names-only 2>/dev/null)" -d "Installed bundle"
complete -c vokun -n "__fish_seen_subcommand_from remove"  -l dry-run  -d "Preview without removing"

# export completes with --json flag
complete -c vokun -n "__fish_seen_subcommand_from export"  -l json -d "Export in JSON format"

# import completes with --dry flag
complete -c vokun -n "__fish_seen_subcommand_from import"  -l dry  -d "Preview changes without applying"

# hook completes with install and remove subcommands
complete -c vokun -n "__fish_seen_subcommand_from hook"    -a "install remove" -d "Hook action"

# help completes with subcommand names
complete -c vokun -n "__fish_seen_subcommand_from help"    -a "$subcommands" -d "Subcommand"
