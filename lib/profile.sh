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
        show|"")    vokun::profile::cmd_show ;;
        *)
            vokun::core::error "Unknown profile subcommand: $subcmd"
            vokun::core::log ""
            vokun::core::log "Subcommands:"
            vokun::core::log "  list               List all profiles"
            vokun::core::log "  switch <name>       Switch to a profile"
            vokun::core::log "  create <name>       Create a new profile"
            vokun::core::log "  delete <name>       Delete a profile"
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
