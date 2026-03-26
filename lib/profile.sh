#!/usr/bin/env bash
# shellcheck disable=SC2034
# vokun - Profile management
# Switch between different bundle configurations for different machines/contexts

VOKUN_PROFILE_FILE=""

# Get the active profile name
vokun::profile::get_active() {
    VOKUN_PROFILE_FILE="${VOKUN_CONFIG_DIR}/.active_profile"
    if [[ -f "$VOKUN_PROFILE_FILE" ]]; then
        cat "$VOKUN_PROFILE_FILE"
    else
        printf 'default'
    fi
}

# Set the active profile
vokun::profile::set_active() {
    local name="$1"
    VOKUN_PROFILE_FILE="${VOKUN_CONFIG_DIR}/.active_profile"
    printf '%s' "$name" > "$VOKUN_PROFILE_FILE"
}

# Get the state file path for a profile
vokun::profile::state_file() {
    local name="${1:-}"
    [[ -z "$name" ]] && name=$(vokun::profile::get_active)

    if [[ "$name" == "default" ]]; then
        printf '%s/state.json' "$VOKUN_CONFIG_DIR"
    else
        printf '%s/state-%s.json' "$VOKUN_CONFIG_DIR" "$name"
    fi
}

# List all profiles
vokun::profile::list_all() {
    local active
    active=$(vokun::profile::get_active)

    # Default always exists
    if [[ "$active" == "default" ]]; then
        printf '%s* default%s\n' "$VOKUN_COLOR_GREEN" "$VOKUN_COLOR_RESET"
    else
        printf '  default\n'
    fi

    # Find other state files
    local f
    for f in "${VOKUN_CONFIG_DIR}"/state-*.json; do
        [[ -f "$f" ]] || continue
        local name
        name=$(basename "$f" | sed 's/^state-//;s/\.json$//')
        if [[ "$name" == "$active" ]]; then
            printf '%s* %s%s\n' "$VOKUN_COLOR_GREEN" "$name" "$VOKUN_COLOR_RESET"
        else
            printf '  %s\n' "$name"
        fi
    done
}

# --- Dispatch ---

vokun::profile::dispatch() {
    local subcmd="${1:-}"
    shift 2>/dev/null || true

    case "$subcmd" in
        list|ls)    vokun::profile::cmd_list ;;
        switch|use) vokun::profile::cmd_switch "$@" ;;
        create|new) vokun::profile::cmd_create "$@" ;;
        delete|rm)  vokun::profile::cmd_delete "$@" ;;
        copy|cp)    vokun::profile::cmd_copy "$@" ;;
        show|"")    vokun::profile::cmd_show ;;
        *)
            vokun::core::error "Unknown profile subcommand: $subcmd"
            vokun::core::log ""
            vokun::core::log "Subcommands:"
            vokun::core::log "  list               List all profiles"
            vokun::core::log "  switch <name>       Switch to a profile"
            vokun::core::log "  create <name>       Create a new profile"
            vokun::core::log "  delete <name>       Delete a profile"
            vokun::core::log "  copy <from> <to>    Copy bundles from one profile to another"
            vokun::core::log "  show               Show active profile"
            return 1
            ;;
    esac
}

# --- vokun profile show ---
vokun::profile::cmd_show() {
    local active
    active=$(vokun::profile::get_active)
    local state_file
    state_file=$(vokun::profile::state_file "$active")

    printf '\n%sActive profile: %s%s%s\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_GREEN" "$active" "$VOKUN_COLOR_RESET"
    printf '%sState file: %s%s\n' "$VOKUN_COLOR_DIM" "$state_file" "$VOKUN_COLOR_RESET"

    if command -v jq &>/dev/null && [[ -f "$state_file" ]]; then
        local bundle_count
        bundle_count=$(jq '.installed_bundles | length' "$state_file" 2>/dev/null || echo "0")
        printf '%sBundles installed: %s%s\n' "$VOKUN_COLOR_DIM" "$bundle_count" "$VOKUN_COLOR_RESET"
    fi
    printf '\n'
}

# --- vokun profile list ---
vokun::profile::cmd_list() {
    printf '\n%sProfiles:%s\n\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET"
    vokun::profile::list_all
    printf '\n'
}

# --- vokun profile switch ---
vokun::profile::cmd_switch() {
    local name="${1:-}"
    if [[ -z "$name" ]]; then
        vokun::core::error "Usage: vokun profile switch <name>"
        return 1
    fi

    local state_file
    state_file=$(vokun::profile::state_file "$name")

    if [[ ! -f "$state_file" && "$name" != "default" ]]; then
        vokun::core::error "Profile '$name' does not exist"
        vokun::core::log "Create it with: vokun profile create $name"
        return 1
    fi

    vokun::profile::set_active "$name"

    # Reinitialize state with the new profile's file
    VOKUN_STATE_FILE="$state_file"

    vokun::core::success "Switched to profile '$name'"
    printf '%sState file: %s%s\n' "$VOKUN_COLOR_DIM" "$state_file" "$VOKUN_COLOR_RESET"
}

# --- vokun profile create ---
vokun::profile::cmd_create() {
    local name="${1:-}"
    if [[ -z "$name" ]]; then
        vokun::core::error "Usage: vokun profile create <name>"
        return 1
    fi

    # Validate name (alphanumeric, hyphens, underscores only)
    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        vokun::core::error "Profile name must be alphanumeric (hyphens and underscores allowed)"
        return 1
    fi

    if [[ "$name" == "default" ]]; then
        vokun::core::warn "The 'default' profile always exists"
        return 0
    fi

    local state_file
    state_file=$(vokun::profile::state_file "$name")

    if [[ -f "$state_file" ]]; then
        vokun::core::warn "Profile '$name' already exists"
        return 0
    fi

    # Create empty state file
    if command -v jq &>/dev/null; then
        jq -n '{version: "1.0.0", installed_bundles: {}, unmanaged: []}' > "$state_file"
    else
        cat > "$state_file" <<'EOF'
{
  "version": "1.0.0",
  "installed_bundles": {},
  "unmanaged": []
}
EOF
    fi

    vokun::core::success "Created profile '$name'"
    printf '%sState file: %s%s\n' "$VOKUN_COLOR_DIM" "$state_file" "$VOKUN_COLOR_RESET"

    printf '\nSwitch to it? [Y/n] '
    local reply
    read -r reply
    case "$reply" in
        [nN]|[nN][oO]) ;;
        *) vokun::profile::cmd_switch "$name" ;;
    esac
}

# --- vokun profile delete ---
vokun::profile::cmd_delete() {
    local name="${1:-}"
    if [[ -z "$name" ]]; then
        vokun::core::error "Usage: vokun profile delete <name>"
        return 1
    fi

    if [[ "$name" == "default" ]]; then
        vokun::core::error "Cannot delete the default profile"
        return 1
    fi

    local state_file
    state_file=$(vokun::profile::state_file "$name")

    if [[ ! -f "$state_file" ]]; then
        vokun::core::error "Profile '$name' does not exist"
        return 1
    fi

    local active
    active=$(vokun::profile::get_active)
    if [[ "$active" == "$name" ]]; then
        vokun::core::warn "This is the active profile. Switching to 'default' first."
        vokun::profile::set_active "default"
        VOKUN_STATE_FILE=$(vokun::profile::state_file "default")
    fi

    if ! vokun::core::confirm "Delete profile '$name'?"; then
        vokun::core::log "Cancelled."
        return 0
    fi

    rm -f "$state_file"
    vokun::core::success "Deleted profile '$name'"
}

# --- vokun profile copy ---
vokun::profile::cmd_copy() {
    local from="${1:-}"
    local to="${2:-}"

    if [[ -z "$from" || -z "$to" ]]; then
        vokun::core::error "Usage: vokun profile copy <from> <to>"
        return 1
    fi

    if ! command -v jq &>/dev/null; then
        vokun::core::error "jq is required for profile copy. Run 'vokun setup' to install it."
        return 1
    fi

    local from_file to_file
    from_file=$(vokun::profile::state_file "$from")
    to_file=$(vokun::profile::state_file "$to")

    if [[ ! -f "$from_file" ]]; then
        vokun::core::error "Source profile '$from' does not exist"
        return 1
    fi

    # Create target profile if it doesn't exist
    if [[ ! -f "$to_file" ]]; then
        vokun::profile::cmd_create "$to" <<< "n"
        to_file=$(vokun::profile::state_file "$to")
    fi

    # Get bundles from source
    local -a from_bundles
    mapfile -t from_bundles < <(jq -r '.installed_bundles | keys[]' "$from_file" 2>/dev/null)

    if [[ ${#from_bundles[@]} -eq 0 ]]; then
        vokun::core::info "Profile '$from' has no installed bundles to copy."
        return 0
    fi

    # Get bundles already in target
    local -a to_bundles
    mapfile -t to_bundles < <(jq -r '.installed_bundles | keys[]' "$to_file" 2>/dev/null)

    local -a new_bundles=()
    local -a existing_bundles=()
    local bundle
    for bundle in "${from_bundles[@]}"; do
        [[ -z "$bundle" ]] && continue
        if jq -e --arg b "$bundle" '.installed_bundles | has($b)' "$to_file" &>/dev/null; then
            existing_bundles+=("$bundle")
        else
            new_bundles+=("$bundle")
        fi
    done

    printf '\n%sCopy profile: %s → %s%s\n' "$VOKUN_COLOR_BOLD" "$from" "$to" "$VOKUN_COLOR_RESET"
    printf '%s\n' "$(printf '%.0s─' {1..50})"

    if [[ ${#new_bundles[@]} -gt 0 ]]; then
        printf '\n  %sBundles to add:%s\n' "$VOKUN_COLOR_GREEN" "$VOKUN_COLOR_RESET"
        for bundle in "${new_bundles[@]}"; do
            printf '    + %s\n' "$bundle"
        done
    fi

    if [[ ${#existing_bundles[@]} -gt 0 ]]; then
        printf '\n  %sAlready in target (will merge packages):%s\n' "$VOKUN_COLOR_DIM" "$VOKUN_COLOR_RESET"
        for bundle in "${existing_bundles[@]}"; do
            printf '    = %s\n' "$bundle"
        done
    fi

    if [[ ${#new_bundles[@]} -eq 0 && ${#existing_bundles[@]} -eq 0 ]]; then
        vokun::core::info "Nothing to copy."
        return 0
    fi

    printf '\n'
    if ! vokun::core::confirm "Copy ${#from_bundles[@]} bundle(s) to profile '$to'?"; then
        vokun::core::log "Cancelled."
        return 0
    fi

    # Merge each bundle from source into target
    local tmp
    for bundle in "${from_bundles[@]}"; do
        [[ -z "$bundle" ]] && continue
        local bundle_data
        bundle_data=$(jq --arg b "$bundle" '.installed_bundles[$b]' "$from_file")

        if jq -e --arg b "$bundle" '.installed_bundles | has($b)' "$to_file" &>/dev/null; then
            # Merge: union packages, keep target's selections unless source has ones target doesn't
            tmp=$(mktemp)
            jq --arg b "$bundle" --argjson src "$bundle_data" '
                .installed_bundles[$b].packages = ([.installed_bundles[$b].packages[], $src.packages[]?] | unique) |
                .installed_bundles[$b].installed_by_vokun = ([.installed_bundles[$b].installed_by_vokun[]?, $src.installed_by_vokun[]?] | unique) |
                .installed_bundles[$b].selections = ((.installed_bundles[$b].selections // {}) + ($src.selections // {}) )
            ' "$to_file" > "$tmp" && mv "$tmp" "$to_file"
        else
            # New bundle: copy entirely
            tmp=$(mktemp)
            jq --arg b "$bundle" --argjson data "$bundle_data" \
                '.installed_bundles[$b] = $data' "$to_file" > "$tmp" && mv "$tmp" "$to_file"
        fi
    done

    # Also copy unmanaged list (merge unique)
    tmp=$(mktemp)
    jq --slurpfile src "$from_file" \
        '.unmanaged = ([.unmanaged[]?, $src[0].unmanaged[]?] | unique)' \
        "$to_file" > "$tmp" && mv "$tmp" "$to_file"

    vokun::core::success "Copied ${#from_bundles[@]} bundle(s) from '$from' to '$to'."
}
