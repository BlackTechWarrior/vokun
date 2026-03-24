#!/usr/bin/env bash
# vokun - State management
# Tracks installed bundles, packages, and skipped packages via JSON (jq)

VOKUN_STATE_FILE=""

vokun::state::init() {
    VOKUN_STATE_FILE="${VOKUN_CONFIG_DIR}/state.json"

    if [[ ! -f "$VOKUN_STATE_FILE" ]]; then
        vokun::state::_create_default
    fi
}

vokun::state::_create_default() {
    if ! command -v jq &>/dev/null; then
        cat > "$VOKUN_STATE_FILE" <<'EOF'
{
  "version": "1.0.0",
  "installed_bundles": {},
  "unmanaged": []
}
EOF
        return
    fi

    jq -n '{
        version: "1.0.0",
        installed_bundles: {},
        unmanaged: []
    }' > "$VOKUN_STATE_FILE"
}

# Check if a bundle is installed
vokun::state::is_installed() {
    local bundle="$1"

    if ! command -v jq &>/dev/null; then
        grep -q "\"$bundle\"" "$VOKUN_STATE_FILE" 2>/dev/null
        return
    fi

    jq -e --arg b "$bundle" '.installed_bundles | has($b)' "$VOKUN_STATE_FILE" &>/dev/null
}

# Get list of installed bundle names
vokun::state::get_installed_bundles() {
    if ! command -v jq &>/dev/null; then
        return
    fi

    jq -r '.installed_bundles | keys[]' "$VOKUN_STATE_FILE" 2>/dev/null
}

# Get packages for an installed bundle
vokun::state::get_bundle_packages() {
    local bundle="$1"

    if ! command -v jq &>/dev/null; then
        return
    fi

    jq -r --arg b "$bundle" '.installed_bundles[$b].packages[]? // empty' "$VOKUN_STATE_FILE" 2>/dev/null
}

# Get all tracked packages across all bundles
vokun::state::get_all_tracked_packages() {
    if ! command -v jq &>/dev/null; then
        return
    fi

    jq -r '[.installed_bundles[].packages[]?] | unique[]' "$VOKUN_STATE_FILE" 2>/dev/null
}

# Record a bundle as installed
# Usage: vokun::state::add_bundle "coding" "git base-devel cmake" "valgrind" "default"
vokun::state::add_bundle() {
    local bundle="$1"
    local packages="$2"  # space-separated
    local skipped="${3:-}"  # space-separated
    local source="${4:-custom}"

    if ! command -v jq &>/dev/null; then
        vokun::core::warn "jq not available — state not saved"
        return
    fi

    # Convert space-separated to JSON arrays
    local pkg_json skipped_json
    pkg_json=$(printf '%s\n' $packages | jq -R . | jq -s .)
    if [[ -n "$skipped" ]]; then
        skipped_json=$(printf '%s\n' $skipped | jq -R . | jq -s .)
    else
        skipped_json='[]'
    fi

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local tmp
    tmp=$(mktemp)
    jq --arg b "$bundle" \
       --arg ts "$timestamp" \
       --arg src "$source" \
       --argjson pkgs "$pkg_json" \
       --argjson skip "$skipped_json" \
       '.installed_bundles[$b] = {
            installed_at: $ts,
            packages: $pkgs,
            skipped: $skip,
            source: $src
        }' "$VOKUN_STATE_FILE" > "$tmp" && mv "$tmp" "$VOKUN_STATE_FILE"
}

# Remove a bundle from state
vokun::state::remove_bundle() {
    local bundle="$1"

    if ! command -v jq &>/dev/null; then
        vokun::core::warn "jq not available — state not updated"
        return
    fi

    local tmp
    tmp=$(mktemp)
    jq --arg b "$bundle" 'del(.installed_bundles[$b])' "$VOKUN_STATE_FILE" > "$tmp" && mv "$tmp" "$VOKUN_STATE_FILE"
}

# Get packages that exist in other bundles (shared packages)
# Returns packages from the given list that appear in OTHER installed bundles
vokun::state::get_shared_packages() {
    local bundle="$1"
    shift
    local -a packages=("$@")

    if ! command -v jq &>/dev/null; then
        return
    fi

    # Get all packages from other bundles
    local other_pkgs
    other_pkgs=$(jq -r --arg b "$bundle" \
        '[.installed_bundles | to_entries[] | select(.key != $b) | .value.packages[]?] | unique[]' \
        "$VOKUN_STATE_FILE" 2>/dev/null)

    local pkg
    for pkg in "${packages[@]}"; do
        if echo "$other_pkgs" | grep -qx "$pkg"; then
            printf '%s\n' "$pkg"
        fi
    done
}
