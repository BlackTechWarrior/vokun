#!/usr/bin/env bash
# shellcheck disable=SC2034
# vokun - Core utilities
# Logging, config, AUR helper detection, help system

# --- Color setup ---

declare -g VOKUN_COLOR_RED=""
declare -g VOKUN_COLOR_GREEN=""
declare -g VOKUN_COLOR_YELLOW=""
declare -g VOKUN_COLOR_BLUE=""
declare -g VOKUN_COLOR_MAGENTA=""
declare -g VOKUN_COLOR_CYAN=""
declare -g VOKUN_COLOR_BOLD=""
declare -g VOKUN_COLOR_DIM=""
declare -g VOKUN_COLOR_RESET=""

vokun::core::setup_colors() {
    # Respect NO_COLOR (https://no-color.org/) and --no-color flag
    if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" && "${VOKUN_NO_COLOR:-}" != "true" ]]; then
        VOKUN_COLOR_RED=$'\033[0;31m'
        VOKUN_COLOR_GREEN=$'\033[0;32m'
        VOKUN_COLOR_YELLOW=$'\033[1;33m'
        VOKUN_COLOR_BLUE=$'\033[0;34m'
        VOKUN_COLOR_MAGENTA=$'\033[0;35m'
        VOKUN_COLOR_CYAN=$'\033[0;36m'
        VOKUN_COLOR_BOLD=$'\033[1m'
        VOKUN_COLOR_DIM=$'\033[2m'
        VOKUN_COLOR_RESET=$'\033[0m'
    fi
}

# --- Logging ---

vokun::core::log() {
    printf '%s\n' "$*"
}

vokun::core::info() {
    printf '%s::%s %s%s\n' "$VOKUN_COLOR_BLUE" "$VOKUN_COLOR_RESET" "$VOKUN_COLOR_BOLD$*" "$VOKUN_COLOR_RESET"
}

vokun::core::success() {
    printf '%s::%s %s%s\n' "$VOKUN_COLOR_GREEN" "$VOKUN_COLOR_RESET" "$*" "$VOKUN_COLOR_RESET"
}

vokun::core::warn() {
    printf '%s:: WARNING:%s %s%s\n' "$VOKUN_COLOR_YELLOW" "$VOKUN_COLOR_RESET" "$*" "$VOKUN_COLOR_RESET" >&2
}

vokun::core::error() {
    printf '%s:: ERROR:%s %s%s\n' "$VOKUN_COLOR_RED" "$VOKUN_COLOR_RESET" "$*" "$VOKUN_COLOR_RESET" >&2
}

vokun::core::dim() {
    printf '%s%s%s' "$VOKUN_COLOR_DIM" "$*" "$VOKUN_COLOR_RESET"
}

# Print the underlying command being run (transparency)
vokun::core::show_cmd() {
    printf '%s=> %s%s\n' "$VOKUN_COLOR_DIM" "$*" "$VOKUN_COLOR_RESET"
}

# --- Action logging ---

VOKUN_LOG_FILE=""

# Initialize the log file
vokun::core::log_init() {
    VOKUN_LOG_FILE="${VOKUN_CONFIG_DIR}/vokun.log"
}

# Write an action to the log file
# Usage: vokun::core::log_action "install" "coding" "git base-devel cmake"
vokun::core::log_action() {
    [[ -z "$VOKUN_LOG_FILE" ]] && return
    local action="$1"
    local target="${2:-}"
    local details="${3:-}"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local profile
    profile=$(vokun::profile::get_active 2>/dev/null || echo "default")
    printf '%s|%s|%s|%s|%s\n' "$timestamp" "$action" "$target" "$details" "$profile" >> "$VOKUN_LOG_FILE"
}

# Read the last N log entries
# Returns pipe-delimited: timestamp|action|target|details|profile
vokun::core::log_read() {
    local count="${1:-10}"
    [[ -z "$VOKUN_LOG_FILE" || ! -f "$VOKUN_LOG_FILE" ]] && return
    tail -n "$count" "$VOKUN_LOG_FILE"
}

# Get the last log entry matching an action type
vokun::core::log_last() {
    local action="${1:-}"
    [[ -z "$VOKUN_LOG_FILE" || ! -f "$VOKUN_LOG_FILE" ]] && return
    if [[ -n "$action" ]]; then
        grep "|${action}|" "$VOKUN_LOG_FILE" | tail -1
    else
        tail -1 "$VOKUN_LOG_FILE"
    fi
}

# Show the action log
# Usage: vokun::core::log_show [--count N]
vokun::core::log_show() {
    local count=20

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --count) count="${2:-20}"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ -z "$VOKUN_LOG_FILE" || ! -f "$VOKUN_LOG_FILE" ]]; then
        vokun::core::info "No actions logged yet."
        return 0
    fi

    printf '\n%sAction Log%s %s(last %d entries)%s\n' \
        "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET" "$VOKUN_COLOR_DIM" "$count" "$VOKUN_COLOR_RESET"
    printf '%s\n\n' "$(printf '%.0s─' {1..60})"

    local line
    while IFS='|' read -r timestamp action target details profile; do
        [[ -z "$timestamp" ]] && continue
        local action_color="$VOKUN_COLOR_CYAN"
        case "$action" in
            *remove*|yeet) action_color="$VOKUN_COLOR_RED" ;;
            *install*|get) action_color="$VOKUN_COLOR_GREEN" ;;
        esac
        printf '  %s%s%s  %s%-15s%s  %s' \
            "$VOKUN_COLOR_DIM" "$timestamp" "$VOKUN_COLOR_RESET" \
            "$action_color" "$action" "$VOKUN_COLOR_RESET" \
            "$target"
        if [[ "$profile" != "default" && -n "$profile" ]]; then
            printf ' %s[%s]%s' "$VOKUN_COLOR_DIM" "$profile" "$VOKUN_COLOR_RESET"
        fi
        printf '\n'
    done < <(tail -n "$count" "$VOKUN_LOG_FILE")

    printf '\n'
}

# --- Confirmation ---

# Prompt user for confirmation
# Returns 0 if confirmed, 1 if declined
# Skipped if --yes flag is set
vokun::core::confirm() {
    local prompt="${1:-Continue?}"

    if [[ "${VOKUN_YES:-false}" == "true" ]]; then
        return 0
    fi

    printf '%s [Y/n] ' "$prompt"
    local reply
    read -r reply
    case "$reply" in
        [nN]|[nN][oO]) return 1 ;;
        *) return 0 ;;
    esac
}

# --- AUR helper detection ---

vokun::core::detect_aur_helper() {
    if command -v paru &>/dev/null; then
        printf 'paru'
    elif command -v yay &>/dev/null; then
        printf 'yay'
    else
        printf ''
    fi
}

# Get the configured or detected AUR helper
vokun::core::get_aur_helper() {
    # Check config first
    if [[ -n "${VOKUN_AUR_HELPER:-}" ]]; then
        printf '%s' "$VOKUN_AUR_HELPER"
        return
    fi

    # Auto-detect
    vokun::core::detect_aur_helper
}

# --- Pacman wrapper ---

# Run a pacman command with transparency
# Automatically uses sudo for operations that need root
# Usage: vokun::core::run_pacman -S package1 package2
#        vokun::core::run_pacman -Ss query
vokun::core::run_pacman() {
    local flags="$1"
    shift

    local cmd="pacman"
    local needs_sudo=false

    # Determine if we need sudo based on the operation
    case "$flags" in
        -S|-S[^s]*|-R*|-U|-Syu|-Syyu|-Sy)
            needs_sudo=true
            ;;
    esac

    # Use AUR helper if available (it handles sudo internally)
    local aur_helper
    aur_helper=$(vokun::core::get_aur_helper)
    if [[ -n "$aur_helper" ]]; then
        cmd="$aur_helper"
        needs_sudo=false  # AUR helpers handle sudo themselves
    fi

    if [[ "$needs_sudo" == true ]]; then
        vokun::core::show_cmd "sudo $cmd $flags $*"
        sudo "$cmd" "$flags" "$@"
    else
        vokun::core::show_cmd "$cmd $flags $*"
        "$cmd" "$flags" "$@"
    fi
}

# Run pacman specifically (not AUR helper) — for operations that must use pacman
vokun::core::run_pacman_only() {
    local flags="$1"
    shift

    local needs_sudo=false
    case "$flags" in
        -S|-S[^s]*|-R*|-U|-Syu|-Syyu|-Sy)
            needs_sudo=true
            ;;
    esac

    if [[ "$needs_sudo" == true ]]; then
        vokun::core::show_cmd "sudo pacman $flags $*"
        sudo pacman "$flags" "$@"
    else
        vokun::core::show_cmd "pacman $flags $*"
        pacman "$flags" "$@"
    fi
}

# --- Config loading ---

vokun::core::load_config() {
    local config_file="${VOKUN_CONFIG_DIR}/vokun.conf"

    # Set defaults
    VOKUN_AUR_HELPER=$(vokun::core::detect_aur_helper)
    VOKUN_CONFIRM=true
    VOKUN_FZF=true
    VOKUN_SYNC_AUTO_PROMPT=true
    VOKUN_AUR_TRUST_THRESHOLD=50
    VOKUN_AUR_WARN_AGE_DAYS=180

    if [[ -f "$config_file" ]]; then
        vokun::toml::parse "$config_file"

        # Apply config values
        local val
        val=$(vokun::toml::get "general.aur_helper")
        [[ -n "$val" ]] && VOKUN_AUR_HELPER="$val"
        val=$(vokun::toml::get "general.confirm")
        [[ -n "$val" ]] && VOKUN_CONFIRM="$val"
        val=$(vokun::toml::get "general.fzf")
        [[ -n "$val" ]] && VOKUN_FZF="$val"
        val=$(vokun::toml::get "sync.auto_prompt")
        [[ -n "$val" ]] && VOKUN_SYNC_AUTO_PROMPT="$val"
        val=$(vokun::toml::get "aur.trust_threshold")
        [[ -n "$val" ]] && VOKUN_AUR_TRUST_THRESHOLD="$val"
        val=$(vokun::toml::get "aur.warn_age_days")
        [[ -n "$val" ]] && VOKUN_AUR_WARN_AGE_DAYS="$val"
    fi
}

# --- Init ---

vokun::core::init() {
    vokun::core::setup_colors
    vokun::core::log_init

    # Create config directory if needed
    mkdir -p "${VOKUN_CONFIG_DIR}"
    mkdir -p "${VOKUN_CONFIG_DIR}/bundles/custom"

    # Load config
    vokun::core::load_config

    # Check for jq (soft dependency)
    if ! command -v jq &>/dev/null; then
        vokun::core::warn "jq is not installed. State tracking will be limited."
        vokun::core::warn "Install it with: sudo pacman -S jq"
    fi
}

# --- Help system ---

vokun::core::help() {
    local command="${1:-}"

    if [[ -z "$command" ]]; then
        vokun::core::help_main
    else
        vokun::core::help_command "$command"
    fi
}

vokun::core::help_main() {
    cat <<EOF
${VOKUN_COLOR_BOLD}vokun${VOKUN_COLOR_RESET} - Package Bundle Manager for Arch Linux ${VOKUN_COLOR_DIM}(v${VOKUN_VERSION})${VOKUN_COLOR_RESET}

${VOKUN_COLOR_BOLD}USAGE${VOKUN_COLOR_RESET}
    vokun <command> [options]

${VOKUN_COLOR_BOLD}BUNDLE COMMANDS${VOKUN_COLOR_RESET}
    ${VOKUN_COLOR_GREEN}install${VOKUN_COLOR_RESET} <bundle>         Install a package bundle
    ${VOKUN_COLOR_GREEN}remove${VOKUN_COLOR_RESET}  <bundle>         Remove a bundle's unique packages
    ${VOKUN_COLOR_GREEN}list${VOKUN_COLOR_RESET}                     List available bundles
    ${VOKUN_COLOR_GREEN}info${VOKUN_COLOR_RESET}    <bundle>         Show bundle details
    ${VOKUN_COLOR_GREEN}search${VOKUN_COLOR_RESET}  <keyword>        Search bundles by name, tag, or package
    ${VOKUN_COLOR_GREEN}bundle${VOKUN_COLOR_RESET}  <action>         Manage bundles ${VOKUN_COLOR_DIM}(create, add, rm, edit, delete)${VOKUN_COLOR_RESET}
    ${VOKUN_COLOR_GREEN}sync${VOKUN_COLOR_RESET}                     Detect packages not tracked in any bundle
    ${VOKUN_COLOR_GREEN}export${VOKUN_COLOR_RESET}  [file]           Export custom bundles and config
    ${VOKUN_COLOR_GREEN}import${VOKUN_COLOR_RESET}  <file>           Import bundles from a file

${VOKUN_COLOR_BOLD}PACKAGE COMMANDS${VOKUN_COLOR_RESET}
    ${VOKUN_COLOR_CYAN}get${VOKUN_COLOR_RESET}     <pkg>            Install a package ${VOKUN_COLOR_DIM}(pacman -S)${VOKUN_COLOR_RESET}
    ${VOKUN_COLOR_CYAN}yeet${VOKUN_COLOR_RESET}    <pkg>            Remove a package ${VOKUN_COLOR_DIM}(pacman -Rns)${VOKUN_COLOR_RESET}
    ${VOKUN_COLOR_CYAN}find${VOKUN_COLOR_RESET}    <query>          Search for packages ${VOKUN_COLOR_DIM}(pacman -Ss)${VOKUN_COLOR_RESET}
    ${VOKUN_COLOR_CYAN}which${VOKUN_COLOR_RESET}   <pkg>            Show package info ${VOKUN_COLOR_DIM}(pacman -Qi)${VOKUN_COLOR_RESET}
    ${VOKUN_COLOR_CYAN}owns${VOKUN_COLOR_RESET}    <file>           Find which package owns a file ${VOKUN_COLOR_DIM}(pacman -Qo)${VOKUN_COLOR_RESET}
    ${VOKUN_COLOR_CYAN}update${VOKUN_COLOR_RESET}                   Full system update ${VOKUN_COLOR_DIM}(pacman -Syu)${VOKUN_COLOR_RESET}

${VOKUN_COLOR_BOLD}MAINTENANCE${VOKUN_COLOR_RESET}
    ${VOKUN_COLOR_YELLOW}orphans${VOKUN_COLOR_RESET}                  List orphaned packages
    ${VOKUN_COLOR_YELLOW}cache${VOKUN_COLOR_RESET}                    Manage package cache
    ${VOKUN_COLOR_YELLOW}size${VOKUN_COLOR_RESET}                     List packages by installed size
    ${VOKUN_COLOR_YELLOW}recent${VOKUN_COLOR_RESET}                   Show recently installed packages
    ${VOKUN_COLOR_YELLOW}foreign${VOKUN_COLOR_RESET}                  List AUR/foreign packages
    ${VOKUN_COLOR_YELLOW}explicit${VOKUN_COLOR_RESET}                 List explicitly installed packages
    ${VOKUN_COLOR_YELLOW}broken${VOKUN_COLOR_RESET}                   Check for broken symlinks and missing deps
    ${VOKUN_COLOR_YELLOW}check${VOKUN_COLOR_RESET}   <pkg>            Check AUR package trust and integrity
    ${VOKUN_COLOR_YELLOW}diff${VOKUN_COLOR_RESET}    <pkg>            Show AUR package PKGBUILD

${VOKUN_COLOR_BOLD}AUTOMATION${VOKUN_COLOR_RESET}
    ${VOKUN_COLOR_MAGENTA}hook${VOKUN_COLOR_RESET}    <action>         Manage pacman hook ${VOKUN_COLOR_DIM}(install, remove)${VOKUN_COLOR_RESET}
    ${VOKUN_COLOR_MAGENTA}profile${VOKUN_COLOR_RESET}  <action>         Manage profiles ${VOKUN_COLOR_DIM}(list, switch, create, delete)${VOKUN_COLOR_RESET}
    ${VOKUN_COLOR_MAGENTA}dotfiles${VOKUN_COLOR_RESET} <action>        Manage dotfiles ${VOKUN_COLOR_DIM}(init, apply, push, pull, status)${VOKUN_COLOR_RESET}
    ${VOKUN_COLOR_MAGENTA}log${VOKUN_COLOR_RESET}                      View action history
    ${VOKUN_COLOR_MAGENTA}rollback${VOKUN_COLOR_RESET}                 Undo the last install or remove
    ${VOKUN_COLOR_MAGENTA}setup${VOKUN_COLOR_RESET}                    Check and install optional dependencies
    ${VOKUN_COLOR_MAGENTA}uninstall${VOKUN_COLOR_RESET}                Remove vokun from your system

${VOKUN_COLOR_BOLD}OPTIONS${VOKUN_COLOR_RESET}
    --dry-run                Show what would happen without doing it
    --yes, -y                Skip confirmation prompts
    --no-color               Disable colored output
    --help, -h               Show this help
    --version, -v            Show version

Run ${VOKUN_COLOR_BOLD}vokun help <command>${VOKUN_COLOR_RESET} for details on a specific command.
EOF
}

vokun::core::help_command() {
    local cmd="$1"
    case "$cmd" in
        install)
            cat <<EOF
${VOKUN_COLOR_BOLD}vokun install${VOKUN_COLOR_RESET} <bundle> [--yes]

Install all packages from a bundle. Shows each package with its description,
highlights AUR packages, and shows optional packages separately.

${VOKUN_COLOR_BOLD}Examples:${VOKUN_COLOR_RESET}
    vokun install coding                      # Install all packages
    vokun install coding --pick               # Interactively select which packages
    vokun install coding --exclude gdb,strace # Skip specific packages
    vokun install coding --only git,cmake     # Install only these from the bundle

${VOKUN_COLOR_BOLD}Flags:${VOKUN_COLOR_RESET}
    --pick                 Interactively select packages (fzf or menu)
    --exclude pkg,pkg,...  Skip these packages
    --only pkg,pkg,...     Install only these packages from the bundle
    --dry-run              Show what would happen without installing
    --yes, -y              Skip confirmation prompt
EOF
            ;;
        remove)
            cat <<EOF
${VOKUN_COLOR_BOLD}vokun remove${VOKUN_COLOR_RESET} <bundle>

Remove packages that are unique to a bundle (not shared with other installed bundles).
Shared packages are kept and listed.

${VOKUN_COLOR_BOLD}Examples:${VOKUN_COLOR_RESET}
    vokun remove gaming
EOF
            ;;
        list)
            cat <<EOF
${VOKUN_COLOR_BOLD}vokun list${VOKUN_COLOR_RESET} [--installed]

List all available bundles, grouped by tags. Installed bundles are highlighted.

${VOKUN_COLOR_BOLD}Flags:${VOKUN_COLOR_RESET}
    --installed    Show only installed bundles
EOF
            ;;
        info)
            cat <<EOF
${VOKUN_COLOR_BOLD}vokun info${VOKUN_COLOR_RESET} <bundle>

Show detailed information about a bundle: description, tags, and all packages
with their descriptions and current install status.

${VOKUN_COLOR_BOLD}Examples:${VOKUN_COLOR_RESET}
    vokun info sysadmin
EOF
            ;;
        search)
            cat <<EOF
${VOKUN_COLOR_BOLD}vokun search${VOKUN_COLOR_RESET} <keyword>

Search across all bundles by name, description, tags, and package names.

${VOKUN_COLOR_BOLD}Examples:${VOKUN_COLOR_RESET}
    vokun search python
    vokun search gaming
EOF
            ;;
        get)
            cat <<EOF
${VOKUN_COLOR_BOLD}vokun get${VOKUN_COLOR_RESET} <package> [package...]

Install one or more packages. Uses paru/yay if available, otherwise pacman.
After installing, prompts to add the package to a bundle.

${VOKUN_COLOR_DIM}Equivalent to: sudo pacman -S <package>${VOKUN_COLOR_RESET}

${VOKUN_COLOR_BOLD}Examples:${VOKUN_COLOR_RESET}
    vokun get neovim
    vokun get firefox chromium
EOF
            ;;
        yeet)
            cat <<EOF
${VOKUN_COLOR_BOLD}vokun yeet${VOKUN_COLOR_RESET} <package> [package...]

Remove packages along with their unneeded dependencies and config files.
Warns if the package belongs to an installed bundle.

${VOKUN_COLOR_DIM}Equivalent to: sudo pacman -Rns <package>${VOKUN_COLOR_RESET}

${VOKUN_COLOR_BOLD}Examples:${VOKUN_COLOR_RESET}
    vokun yeet firefox
EOF
            ;;
        find)
            cat <<EOF
${VOKUN_COLOR_BOLD}vokun find${VOKUN_COLOR_RESET} <query> [--aur]

Search for packages in the repositories (and optionally AUR).

${VOKUN_COLOR_DIM}Equivalent to: pacman -Ss <query>${VOKUN_COLOR_RESET}

${VOKUN_COLOR_BOLD}Flags:${VOKUN_COLOR_RESET}
    --aur    Include AUR results (requires paru/yay)

${VOKUN_COLOR_BOLD}Examples:${VOKUN_COLOR_RESET}
    vokun find terminal
    vokun find --aur spotify
EOF
            ;;
        which)
            cat <<EOF
${VOKUN_COLOR_BOLD}vokun which${VOKUN_COLOR_RESET} <package>

Show detailed information about an installed package.

${VOKUN_COLOR_DIM}Equivalent to: pacman -Qi <package>${VOKUN_COLOR_RESET}
EOF
            ;;
        owns)
            cat <<EOF
${VOKUN_COLOR_BOLD}vokun owns${VOKUN_COLOR_RESET} <file>

Find which package owns a file on your system.

${VOKUN_COLOR_DIM}Equivalent to: pacman -Qo <file>${VOKUN_COLOR_RESET}

${VOKUN_COLOR_BOLD}Examples:${VOKUN_COLOR_RESET}
    vokun owns /usr/bin/git
EOF
            ;;
        update)
            cat <<EOF
${VOKUN_COLOR_BOLD}vokun update${VOKUN_COLOR_RESET} [--aur]

Perform a full system update. Syncs repos and upgrades all packages.

${VOKUN_COLOR_DIM}Equivalent to: sudo pacman -Syu${VOKUN_COLOR_RESET}

${VOKUN_COLOR_BOLD}Flags:${VOKUN_COLOR_RESET}
    --aur    Also update AUR packages (requires paru/yay)
EOF
            ;;
        orphans)
            cat <<EOF
${VOKUN_COLOR_BOLD}vokun orphans${VOKUN_COLOR_RESET} [--clean]

List packages that were installed as dependencies but are no longer required.

${VOKUN_COLOR_DIM}Equivalent to: pacman -Qdt${VOKUN_COLOR_RESET}

${VOKUN_COLOR_BOLD}Flags:${VOKUN_COLOR_RESET}
    --clean    Remove all orphaned packages
EOF
            ;;
        cache)
            cat <<EOF
${VOKUN_COLOR_BOLD}vokun cache${VOKUN_COLOR_RESET} [--clean|--purge]

Show package cache statistics.

${VOKUN_COLOR_BOLD}Flags:${VOKUN_COLOR_RESET}
    --clean    Keep only the last 2 versions of each package
    --purge    Remove all cached packages

${VOKUN_COLOR_DIM}Uses: paccache from pacman-contrib${VOKUN_COLOR_RESET}
EOF
            ;;
        size)
            cat <<EOF
${VOKUN_COLOR_BOLD}vokun size${VOKUN_COLOR_RESET} [--top N]

List installed packages sorted by size (largest first).

${VOKUN_COLOR_BOLD}Flags:${VOKUN_COLOR_RESET}
    --top N    Show only the top N packages (default: 20)
EOF
            ;;
        recent)
            cat <<EOF
${VOKUN_COLOR_BOLD}vokun recent${VOKUN_COLOR_RESET} [--count N]

Show recently installed packages from the pacman log.

${VOKUN_COLOR_BOLD}Flags:${VOKUN_COLOR_RESET}
    --count N    Number of entries to show (default: 20)
EOF
            ;;
        foreign)
            cat <<EOF
${VOKUN_COLOR_BOLD}vokun foreign${VOKUN_COLOR_RESET}

List all packages not found in the sync databases (typically AUR packages).

${VOKUN_COLOR_DIM}Equivalent to: pacman -Qm${VOKUN_COLOR_RESET}
EOF
            ;;
        explicit)
            cat <<EOF
${VOKUN_COLOR_BOLD}vokun explicit${VOKUN_COLOR_RESET}

List all explicitly installed packages (not pulled in as dependencies).

${VOKUN_COLOR_DIM}Equivalent to: pacman -Qe${VOKUN_COLOR_RESET}
EOF
            ;;
        bundle)
            cat <<EOF
${VOKUN_COLOR_BOLD}vokun bundle${VOKUN_COLOR_RESET} <action> [args...]

Manage custom bundles.

${VOKUN_COLOR_BOLD}Actions:${VOKUN_COLOR_RESET}
    create <name>              Create a new custom bundle interactively
    add <bundle> <pkg> ...     Add packages to a bundle
    rm <bundle> <pkg> ...      Remove packages from a bundle
    edit <bundle>              Edit a bundle (fzf picker or \$EDITOR)
    delete <name>              Delete a custom bundle
EOF
            ;;
        sync)
            cat <<EOF
${VOKUN_COLOR_BOLD}vokun sync${VOKUN_COLOR_RESET} [--auto]

Detect explicitly installed packages that are not tracked in any bundle.
Offers to add them to a bundle, create a new bundle, or mark as unmanaged.

${VOKUN_COLOR_BOLD}Flags:${VOKUN_COLOR_RESET}
    --auto    List untracked packages without prompting
EOF
            ;;
        check)
            cat <<EOF
${VOKUN_COLOR_BOLD}vokun check${VOKUN_COLOR_RESET} <package>

Check the trust and integrity of an AUR package. Shows votes, maintainer,
popularity, last update date, and a color-coded trust level.
EOF
            ;;
        diff)
            cat <<EOF
${VOKUN_COLOR_BOLD}vokun diff${VOKUN_COLOR_RESET} <package>

Show the PKGBUILD for an AUR package for manual review.
EOF
            ;;
        export)
            cat <<EOF
${VOKUN_COLOR_BOLD}vokun export${VOKUN_COLOR_RESET} [file] [--json]

Export custom bundles, state, and config to a portable file.
Default output: ./vokun-export.tar.gz

${VOKUN_COLOR_BOLD}Flags:${VOKUN_COLOR_RESET}
    --json    Export as JSON instead of tarball
EOF
            ;;
        import)
            cat <<EOF
${VOKUN_COLOR_BOLD}vokun import${VOKUN_COLOR_RESET} <file> [--dry]

Import bundles from a previously exported file (.tar.gz or .json).

${VOKUN_COLOR_BOLD}Flags:${VOKUN_COLOR_RESET}
    --dry    Preview what would be imported without making changes
EOF
            ;;
        broken)
            cat <<EOF
${VOKUN_COLOR_BOLD}vokun broken${VOKUN_COLOR_RESET}

Check system integrity: broken symlinks, missing dependencies, and
packages with missing files.
EOF
            ;;
        hook)
            cat <<EOF
${VOKUN_COLOR_BOLD}vokun hook${VOKUN_COLOR_RESET} <action>

Manage the pacman hook that notifies about untracked packages.

${VOKUN_COLOR_BOLD}Actions:${VOKUN_COLOR_RESET}
    install    Install the pacman hook (requires sudo)
    remove     Remove the pacman hook (requires sudo)
EOF
            ;;
        log)
            cat <<EOF
${VOKUN_COLOR_BOLD}vokun log${VOKUN_COLOR_RESET} [--count N]

Show the action history log. Displays timestamped entries for bundle
installs, removes, package operations, and rollbacks.
Default: last 20 entries.
EOF
            ;;
        rollback)
            cat <<EOF
${VOKUN_COLOR_BOLD}vokun rollback${VOKUN_COLOR_RESET}

Undo the last reversible action (bundle install, remove, get, or yeet).
Shows what will be undone and confirms before proceeding.
EOF
            ;;
        dotfiles)
            cat <<EOF
${VOKUN_COLOR_BOLD}vokun dotfiles${VOKUN_COLOR_RESET} <action>

Manage dotfiles through your preferred tool (chezmoi, yadm, or stow).
Vokun auto-detects which tool is installed and wraps it safely.

${VOKUN_COLOR_BOLD}Actions:${VOKUN_COLOR_RESET}
    init [repo]        Initialize dotfile management (clone a repo)
    apply              Preview and apply dotfile changes
    push               Commit and push dotfile changes to remote
    pull               Pull latest dotfiles from remote
    status             Show dotfile backend and stats
    edit <file>        Edit a managed dotfile

All destructive actions show a preview and require confirmation.
EOF
            ;;
        profile)
            cat <<EOF
${VOKUN_COLOR_BOLD}vokun profile${VOKUN_COLOR_RESET} <action>

Manage named profiles for different machines or contexts. Each profile has
its own state file tracking which bundles are installed.

${VOKUN_COLOR_BOLD}Actions:${VOKUN_COLOR_RESET}
    show               Show active profile (default)
    list               List all profiles
    switch <name>      Switch to a different profile
    create <name>      Create a new profile
    delete <name>      Delete a profile

${VOKUN_COLOR_BOLD}Examples:${VOKUN_COLOR_RESET}
    vokun profile create workstation
    vokun profile switch server
    vokun profile list
EOF
            ;;
        setup)
            cat <<EOF
${VOKUN_COLOR_BOLD}vokun setup${VOKUN_COLOR_RESET}

Check all optional dependencies and offer to install missing ones.
Also bootstraps paru (AUR helper) from source if no AUR helper is found.

${VOKUN_COLOR_BOLD}Dependencies checked:${VOKUN_COLOR_RESET}
    jq              JSON state tracking (recommended)
    fzf             Interactive fuzzy picker
    paru/yay        AUR package support
    pacman-contrib  Cache management (paccache)
EOF
            ;;
        uninstall)
            cat <<EOF
${VOKUN_COLOR_BOLD}vokun uninstall${VOKUN_COLOR_RESET}

Completely remove vokun from your system. Removes the binary, libraries,
bundles, completions, and pacman hook. Optionally removes your config
directory (~/.config/vokun) with custom bundles and state.

No packages that vokun installed are removed — only vokun itself.
EOF
            ;;
        *)
            vokun::core::error "Unknown command: $cmd"
            vokun::core::log "Run 'vokun help' for a list of commands."
            return 1
            ;;
    esac
}

# --- Utilities ---

vokun::core::unknown() {
    local cmd="$1"
    vokun::core::error "Unknown command: $cmd"
    vokun::core::log ""
    vokun::core::log "Available commands:"
    vokun::core::log "  install, remove, list, info, search, bundle, sync"
    vokun::core::log "  export, import"
    vokun::core::log "  get, yeet, find, which, owns, update"
    vokun::core::log "  orphans, cache, size, recent, foreign, explicit"
    vokun::core::log "  broken, check, diff, hook, profile, dotfiles"
    vokun::core::log "  log, rollback, setup, uninstall"
    vokun::core::log ""
    vokun::core::log "Run 'vokun help' for more information."
    return 1
}

# Check if a value is in an array
# Usage: vokun::core::in_array "value" "${array[@]}"
vokun::core::in_array() {
    local needle="$1"
    shift
    local item
    for item in "$@"; do
        [[ "$item" == "$needle" ]] && return 0
    done
    return 1
}

# Check if a package is installed
vokun::core::is_pkg_installed() {
    local pkg="$1"
    pacman -Qi "$pkg" &>/dev/null
}
