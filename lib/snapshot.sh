#!/usr/bin/env bash
# shellcheck disable=SC2034
# vokun - Snapshot command
# Save, list, diff, restore, and delete system snapshots

VOKUN_SNAPSHOT_DIR=""

vokun::snapshot::init() {
    VOKUN_SNAPSHOT_DIR="${VOKUN_CONFIG_DIR}/snapshots"
    mkdir -p "$VOKUN_SNAPSHOT_DIR"
}

vokun::snapshot::dispatch() {
    vokun::snapshot::init

    local subcmd="${1:-}"
    shift 2>/dev/null || true

    case "$subcmd" in
        create)  vokun::snapshot::create "$@" ;;
        list)    vokun::snapshot::list "$@" ;;
        diff)    vokun::snapshot::diff "$@" ;;
        restore) vokun::snapshot::restore "$@" ;;
        delete)  vokun::snapshot::delete "$@" ;;
        --help|-h|"")
            vokun::core::help_command "snapshot"
            ;;
        *)
            vokun::core::error "Unknown snapshot subcommand: $subcmd"
            vokun::core::log "Available: create, list, diff, restore, delete"
            return 1
            ;;
    esac
}

# --- vokun snapshot create ---

vokun::snapshot::create() {
    local name=""

    for arg in "$@"; do
        case "$arg" in
            --help|-h)
                vokun::core::help_command "snapshot"
                return 0
                ;;
            *) [[ -z "$name" ]] && name="$arg" ;;
        esac
    done

    if [[ -z "$name" ]]; then
        vokun::core::error "Usage: vokun snapshot create <name>"
        return 1
    fi

    # Validate name
    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        vokun::core::error "Snapshot name must be alphanumeric (hyphens and underscores allowed)"
        return 1
    fi

    local snapshot_dir="${VOKUN_SNAPSHOT_DIR}/${name}"

    if [[ -d "$snapshot_dir" ]]; then
        vokun::core::error "Snapshot '$name' already exists"
        vokun::core::log "Delete it first: vokun snapshot delete $name"
        return 1
    fi

    mkdir -p "$snapshot_dir"

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Save metadata
    printf '%s\n' "$timestamp" > "${snapshot_dir}/timestamp"

    local profile
    profile=$(vokun::profile::get_active 2>/dev/null || echo "default")
    printf '%s\n' "$profile" > "${snapshot_dir}/profile"

    # Save explicitly installed packages
    pacman -Qe > "${snapshot_dir}/packages.txt"

    # Save vokun state
    if [[ -f "$VOKUN_STATE_FILE" ]]; then
        cp "$VOKUN_STATE_FILE" "${snapshot_dir}/state.json"
    fi

    # Count packages
    local pkg_count
    pkg_count=$(wc -l < "${snapshot_dir}/packages.txt")

    local bundle_count=0
    if [[ -f "${snapshot_dir}/state.json" ]] && command -v jq &>/dev/null; then
        bundle_count=$(jq '.installed_bundles | length' "${snapshot_dir}/state.json" 2>/dev/null || echo 0)
    fi

    vokun::core::log_action "snapshot-create" "$name" "${pkg_count} packages, ${bundle_count} bundles"
    vokun::core::success "Snapshot '$name' created ($pkg_count packages, $bundle_count bundles)"
}

# --- vokun snapshot list ---

vokun::snapshot::list() {
    for arg in "$@"; do
        case "$arg" in
            --help|-h)
                vokun::core::help_command "snapshot"
                return 0
                ;;
        esac
    done

    local -a snapshots=()
    local d
    for d in "$VOKUN_SNAPSHOT_DIR"/*/; do
        [[ -d "$d" ]] || continue
        snapshots+=("$d")
    done

    if [[ ${#snapshots[@]} -eq 0 ]]; then
        vokun::core::info "No snapshots found."
        vokun::core::log "Create one with: vokun snapshot create <name>"
        return 0
    fi

    printf '\n%sSaved Snapshots%s\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET"
    printf '%s\n\n' "$(printf '%.0s─' {1..50})"

    for d in "${snapshots[@]}"; do
        local name
        name=$(basename "$d")
        local timestamp=""
        [[ -f "${d}timestamp" ]] && timestamp=$(cat "${d}timestamp")
        local pkg_count=0
        [[ -f "${d}packages.txt" ]] && pkg_count=$(wc -l < "${d}packages.txt")
        local profile=""
        [[ -f "${d}profile" ]] && profile=$(cat "${d}profile")

        printf '  %s%-20s%s  %s%s%s  %d packages' \
            "$VOKUN_COLOR_BOLD" "$name" "$VOKUN_COLOR_RESET" \
            "$VOKUN_COLOR_DIM" "$timestamp" "$VOKUN_COLOR_RESET" \
            "$pkg_count"
        if [[ -n "$profile" && "$profile" != "default" ]]; then
            printf '  %s[%s]%s' "$VOKUN_COLOR_DIM" "$profile" "$VOKUN_COLOR_RESET"
        fi
        printf '\n'
    done
    printf '\n'
}

# --- vokun snapshot diff ---

vokun::snapshot::diff() {
    local name=""

    for arg in "$@"; do
        case "$arg" in
            --help|-h)
                vokun::core::help_command "snapshot"
                return 0
                ;;
            *) [[ -z "$name" ]] && name="$arg" ;;
        esac
    done

    if [[ -z "$name" ]]; then
        vokun::core::error "Usage: vokun snapshot diff <name>"
        return 1
    fi

    local snapshot_dir="${VOKUN_SNAPSHOT_DIR}/${name}"
    if [[ ! -d "$snapshot_dir" ]]; then
        vokun::core::error "Snapshot not found: $name"
        return 1
    fi

    if [[ ! -f "${snapshot_dir}/packages.txt" ]]; then
        vokun::core::error "Snapshot is corrupt: missing packages.txt"
        return 1
    fi

    # Get current and snapshot package lists (name only, no versions)
    local current_pkgs snapshot_pkgs
    current_pkgs=$(pacman -Qe | awk '{print $1}' | sort)
    snapshot_pkgs=$(awk '{print $1}' "${snapshot_dir}/packages.txt" | sort)

    # Packages added since snapshot
    local added
    added=$(comm -13 <(printf '%s\n' "$snapshot_pkgs") <(printf '%s\n' "$current_pkgs") | sed '/^$/d')

    # Packages removed since snapshot
    local removed
    removed=$(comm -23 <(printf '%s\n' "$snapshot_pkgs") <(printf '%s\n' "$current_pkgs") | sed '/^$/d')

    printf '\n%sSnapshot diff: %s%s\n' "$VOKUN_COLOR_BOLD" "$name" "$VOKUN_COLOR_RESET"
    local timestamp=""
    [[ -f "${snapshot_dir}/timestamp" ]] && timestamp=$(cat "${snapshot_dir}/timestamp")
    [[ -n "$timestamp" ]] && printf '%sCreated: %s%s\n' "$VOKUN_COLOR_DIM" "$timestamp" "$VOKUN_COLOR_RESET"
    printf '%s\n' "$(printf '%.0s─' {1..50})"

    local has_changes=false

    if [[ -n "$added" ]]; then
        has_changes=true
        local count
        count=$(echo "$added" | wc -l)
        printf '\n  %sPackages added (+%d):%s\n' "$VOKUN_COLOR_GREEN" "$count" "$VOKUN_COLOR_RESET"
        while IFS= read -r pkg; do
            printf '    %s+ %s%s\n' "$VOKUN_COLOR_GREEN" "$pkg" "$VOKUN_COLOR_RESET"
        done <<< "$added"
    fi

    if [[ -n "$removed" ]]; then
        has_changes=true
        local count
        count=$(echo "$removed" | wc -l)
        printf '\n  %sPackages removed (-%d):%s\n' "$VOKUN_COLOR_RED" "$count" "$VOKUN_COLOR_RESET"
        while IFS= read -r pkg; do
            printf '    %s- %s%s\n' "$VOKUN_COLOR_RED" "$pkg" "$VOKUN_COLOR_RESET"
        done <<< "$removed"
    fi

    # Bundle diff
    if [[ -f "${snapshot_dir}/state.json" && -f "$VOKUN_STATE_FILE" ]] && command -v jq &>/dev/null; then
        local current_bundles snapshot_bundles
        current_bundles=$(jq -r '.installed_bundles | keys[]' "$VOKUN_STATE_FILE" 2>/dev/null | sort)
        snapshot_bundles=$(jq -r '.installed_bundles | keys[]' "${snapshot_dir}/state.json" 2>/dev/null | sort)

        local bundles_added bundles_removed
        bundles_added=$(comm -13 <(printf '%s\n' "$snapshot_bundles") <(printf '%s\n' "$current_bundles") | sed '/^$/d')
        bundles_removed=$(comm -23 <(printf '%s\n' "$snapshot_bundles") <(printf '%s\n' "$current_bundles") | sed '/^$/d')

        if [[ -n "$bundles_added" || -n "$bundles_removed" ]]; then
            has_changes=true
            printf '\n  %sBundle changes:%s\n' "$VOKUN_COLOR_CYAN" "$VOKUN_COLOR_RESET"
            if [[ -n "$bundles_added" ]]; then
                while IFS= read -r b; do
                    printf '    %s+ %s%s\n' "$VOKUN_COLOR_GREEN" "$b" "$VOKUN_COLOR_RESET"
                done <<< "$bundles_added"
            fi
            if [[ -n "$bundles_removed" ]]; then
                while IFS= read -r b; do
                    printf '    %s- %s%s\n' "$VOKUN_COLOR_RED" "$b" "$VOKUN_COLOR_RESET"
                done <<< "$bundles_removed"
            fi
        fi
    fi

    if [[ "$has_changes" == false ]]; then
        vokun::core::success "No changes since snapshot '$name'"
    fi

    printf '\n'
}

# --- vokun snapshot restore ---

vokun::snapshot::restore() {
    local name=""
    local dry_run=false

    for arg in "$@"; do
        case "$arg" in
            --dry-run) dry_run=true ;;
            --help|-h)
                vokun::core::help_command "snapshot"
                return 0
                ;;
            *) [[ -z "$name" ]] && name="$arg" ;;
        esac
    done

    if [[ -z "$name" ]]; then
        vokun::core::error "Usage: vokun snapshot restore <name> [--dry-run]"
        return 1
    fi

    local snapshot_dir="${VOKUN_SNAPSHOT_DIR}/${name}"
    if [[ ! -d "$snapshot_dir" ]]; then
        vokun::core::error "Snapshot not found: $name"
        return 1
    fi

    if [[ ! -f "${snapshot_dir}/packages.txt" ]]; then
        vokun::core::error "Snapshot is corrupt: missing packages.txt"
        return 1
    fi

    # Get current and snapshot package lists (name only)
    local current_pkgs snapshot_pkgs
    current_pkgs=$(pacman -Qe | awk '{print $1}' | sort)
    snapshot_pkgs=$(awk '{print $1}' "${snapshot_dir}/packages.txt" | sort)

    # Packages to install (in snapshot but not current)
    local to_install
    to_install=$(comm -23 <(printf '%s\n' "$snapshot_pkgs") <(printf '%s\n' "$current_pkgs") | sed '/^$/d')

    # Packages to remove (in current but not snapshot)
    local to_remove
    to_remove=$(comm -13 <(printf '%s\n' "$snapshot_pkgs") <(printf '%s\n' "$current_pkgs") | sed '/^$/d')

    printf '\n%sRestore snapshot: %s%s\n' "$VOKUN_COLOR_BOLD" "$name" "$VOKUN_COLOR_RESET"
    printf '%s\n' "$(printf '%.0s─' {1..50})"

    local has_work=false

    if [[ -n "$to_install" ]]; then
        has_work=true
        local count
        count=$(echo "$to_install" | wc -l)
        printf '\n  %sPackages to install (%d):%s\n' "$VOKUN_COLOR_GREEN" "$count" "$VOKUN_COLOR_RESET"
        while IFS= read -r pkg; do
            printf '    + %s\n' "$pkg"
        done <<< "$to_install"
    fi

    if [[ -n "$to_remove" ]]; then
        has_work=true
        local count
        count=$(echo "$to_remove" | wc -l)
        printf '\n  %sPackages to remove (%d):%s\n' "$VOKUN_COLOR_RED" "$count" "$VOKUN_COLOR_RESET"
        while IFS= read -r pkg; do
            printf '    - %s\n' "$pkg"
        done <<< "$to_remove"
    fi

    if [[ "$has_work" == false ]]; then
        vokun::core::success "System already matches snapshot '$name'"
        return 0
    fi

    printf '\n'

    if [[ "$dry_run" == true ]]; then
        printf '  %s[DRY RUN] Commands that would be executed:%s\n\n' "$VOKUN_COLOR_YELLOW" "$VOKUN_COLOR_RESET"
        if [[ -n "$to_install" ]]; then
            local install_list
            install_list=$(echo "$to_install" | tr '\n' ' ')
            local helper
            helper=$(vokun::core::get_aur_helper)
            printf '    %s -S --needed %s\n' "${helper:-sudo pacman}" "$install_list"
        fi
        if [[ -n "$to_remove" ]]; then
            local remove_list
            remove_list=$(echo "$to_remove" | tr '\n' ' ')
            printf '    sudo pacman -Rns %s\n' "$remove_list"
        fi
        printf '\n  %sNo changes were made.%s\n\n' "$VOKUN_COLOR_DIM" "$VOKUN_COLOR_RESET"
        return 0
    fi

    if ! vokun::core::confirm "Restore system to snapshot '$name'?"; then
        vokun::core::log "Restore cancelled."
        return 1
    fi

    printf '\n'

    # Install missing packages
    if [[ -n "$to_install" ]]; then
        local -a install_arr
        mapfile -t install_arr <<< "$to_install"
        vokun::core::run_pacman "-S" "--needed" "${install_arr[@]}" || {
            vokun::core::error "Some packages failed to install"
        }
    fi

    # Remove extra packages
    if [[ -n "$to_remove" ]]; then
        local -a remove_arr
        mapfile -t remove_arr <<< "$to_remove"
        vokun::core::run_pacman_only "-Rns" "${remove_arr[@]}" || {
            vokun::core::error "Some packages failed to remove"
        }
    fi

    # Restore vokun state
    if [[ -f "${snapshot_dir}/state.json" ]]; then
        cp "${snapshot_dir}/state.json" "$VOKUN_STATE_FILE"
        vokun::state::init
    fi

    vokun::core::log_action "snapshot-restore" "$name" ""

    printf '\n'
    vokun::core::success "System restored to snapshot '$name'"
}

# --- vokun snapshot delete ---

vokun::snapshot::delete() {
    local name=""

    for arg in "$@"; do
        case "$arg" in
            --help|-h)
                vokun::core::help_command "snapshot"
                return 0
                ;;
            *) [[ -z "$name" ]] && name="$arg" ;;
        esac
    done

    if [[ -z "$name" ]]; then
        vokun::core::error "Usage: vokun snapshot delete <name>"
        return 1
    fi

    local snapshot_dir="${VOKUN_SNAPSHOT_DIR}/${name}"
    if [[ ! -d "$snapshot_dir" ]]; then
        vokun::core::error "Snapshot not found: $name"
        return 1
    fi

    if ! vokun::core::confirm "Delete snapshot '$name'?"; then
        return 1
    fi

    rm -rf "$snapshot_dir"
    vokun::core::log_action "snapshot-delete" "$name" ""
    vokun::core::success "Snapshot '$name' deleted."
}
