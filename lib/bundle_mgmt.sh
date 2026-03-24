#!/usr/bin/env bash
# shellcheck disable=SC2034
# vokun - Bundle management
# create, add, rm, edit, delete

# --- Dispatch ---

vokun::bundle_mgmt::dispatch() {
    local subcmd="${1:-}"

    if [[ -z "$subcmd" ]]; then
        vokun::core::error "Usage: vokun bundle <subcommand> [args...]"
        vokun::core::log ""
        vokun::core::log "Subcommands:"
        vokun::core::log "  create <name>              Create a new bundle"
        vokun::core::log "  add <bundle> <pkg> [...]   Add packages to a bundle"
        vokun::core::log "  rm <bundle> <pkg> [...]    Remove packages from a bundle"
        vokun::core::log "  edit <bundle>              Edit a bundle interactively"
        vokun::core::log "  delete <name>              Delete a custom bundle"
        return 1
    fi

    shift
    case "$subcmd" in
        create) vokun::bundle_mgmt::create "$@" ;;
        add)    vokun::bundle_mgmt::add "$@" ;;
        rm)     vokun::bundle_mgmt::rm "$@" ;;
        edit)   vokun::bundle_mgmt::edit "$@" ;;
        delete) vokun::bundle_mgmt::delete "$@" ;;
        *)
            vokun::core::error "Unknown bundle subcommand: $subcmd"
            vokun::core::log "Run 'vokun bundle' for usage."
            return 1
            ;;
    esac
}

# --- Helpers ---

# Check if a bundle file lives in the system defaults directory
vokun::bundle_mgmt::_is_default_bundle() {
    local file="$1"
    [[ -n "$VOKUN_SYSTEM_BUNDLE_DIR" && "$file" == "${VOKUN_SYSTEM_BUNDLE_DIR}/"* ]]
}

# Copy a default bundle to the custom directory so it can be modified
# Prints the new path
vokun::bundle_mgmt::_copy_to_custom() {
    local file="$1"
    local name
    name=$(vokun::bundles::name_from_path "$file")
    local custom_file="${VOKUN_CONFIG_DIR}/bundles/custom/${name}.toml"

    mkdir -p "${VOKUN_CONFIG_DIR}/bundles/custom"
    cp "$file" "$custom_file"
    vokun::core::info "Copied default bundle to custom: ${custom_file}"
    printf '%s' "$custom_file"
}

# Get the package description from pacman -Si
vokun::bundle_mgmt::_pkg_description() {
    local pkg="$1"
    local desc
    desc=$(pacman -Si "$pkg" 2>/dev/null | sed -n 's/^Description[[:space:]]*:[[:space:]]*//p')
    printf '%s' "$desc"
}

# --- vokun bundle create ---

vokun::bundle_mgmt::create() {
    local name="${1:-}"

    if [[ -z "$name" ]]; then
        vokun::core::error "Usage: vokun bundle create <name>"
        return 1
    fi

    local custom_dir="${VOKUN_CONFIG_DIR}/bundles/custom"
    local bundle_file="${custom_dir}/${name}.toml"

    # Check if bundle already exists
    if vokun::bundles::find_by_name "$name" &>/dev/null; then
        vokun::core::error "Bundle '$name' already exists"
        return 1
    fi

    mkdir -p "$custom_dir"

    # Ask for description
    printf 'Description: '
    local description
    read -r description
    [[ -z "$description" ]] && description="Custom bundle"

    # Ask for tags
    printf 'Tags (comma-separated): '
    local tags_input
    read -r tags_input

    # Build tags array string
    local tags_toml=""
    if [[ -n "$tags_input" ]]; then
        local IFS=','
        local first=true
        tags_toml="["
        # shellcheck disable=SC2086
        for tag in $tags_input; do
            # Trim whitespace
            tag="${tag#"${tag%%[![:space:]]*}"}"
            tag="${tag%"${tag##*[![:space:]]}"}"
            [[ -z "$tag" ]] && continue
            if [[ "$first" == true ]]; then
                tags_toml+="\"${tag}\""
                first=false
            else
                tags_toml+=", \"${tag}\""
            fi
        done
        tags_toml+="]"
    else
        tags_toml='["custom"]'
    fi

    # Write initial TOML
    cat > "$bundle_file" <<EOF
[meta]
name = "${name}"
description = "${description}"
tags = ${tags_toml}
version = "1.0.0"

[packages]
EOF

    # Optionally select packages with fzf
    if command -v fzf &>/dev/null && [[ "${VOKUN_FZF:-true}" == "true" ]]; then
        vokun::core::info "Select packages with fzf (TAB to select, ENTER to confirm)"
        local -a selected
        mapfile -t selected < <(pacman -Slq 2>/dev/null | fzf --multi --prompt="Select packages> " --preview="pacman -Si {1} 2>/dev/null" || true)

        if [[ ${#selected[@]} -gt 0 ]]; then
            for pkg in "${selected[@]}"; do
                [[ -z "$pkg" ]] && continue
                local desc
                desc=$(vokun::bundle_mgmt::_pkg_description "$pkg")
                printf '%s = "%s"\n' "$pkg" "$desc" >> "$bundle_file"
            done
            vokun::core::success "Created bundle '$name' with ${#selected[@]} package(s)"
        else
            vokun::core::success "Created empty bundle '$name'"
        fi
    else
        vokun::core::success "Created empty bundle '$name'"
        vokun::core::log "Edit it with: vokun bundle edit $name"
    fi

    vokun::core::log "Bundle file: ${bundle_file}"
}

# --- vokun bundle add ---

vokun::bundle_mgmt::add() {
    local bundle_name="${1:-}"
    shift 2>/dev/null || true

    if [[ -z "$bundle_name" || $# -eq 0 ]]; then
        vokun::core::error "Usage: vokun bundle add <bundle> <pkg> [pkg...]"
        return 1
    fi

    local file
    file=$(vokun::bundles::find_by_name "$bundle_name") || {
        vokun::core::error "Bundle not found: $bundle_name"
        return 1
    }

    # Never modify system defaults — copy to custom first
    if vokun::bundle_mgmt::_is_default_bundle "$file"; then
        file=$(vokun::bundle_mgmt::_copy_to_custom "$file")
    fi

    local -a added=()
    local pkg
    for pkg in "$@"; do
        # Check if package already exists in the file
        if grep -q "^${pkg}[[:space:]]*=" "$file"; then
            vokun::core::warn "Package '$pkg' already in bundle '$bundle_name'"
            continue
        fi

        local desc
        desc=$(vokun::bundle_mgmt::_pkg_description "$pkg")

        # Append to the [packages] section
        # Find the last line of the [packages] section (before next section or EOF)
        # Use sed to insert after the [packages] block
        local tmp
        tmp=$(mktemp)
        awk -v pkg="$pkg" -v desc="$desc" '
            /^\[packages\]/ { in_pkg=1; print; next }
            in_pkg && /^\[/ { print pkg " = \"" desc "\""; print ""; in_pkg=0 }
            { print }
            END { if (in_pkg) print pkg " = \"" desc "\"" }
        ' "$file" > "$tmp" && mv "$tmp" "$file"

        added+=("$pkg")
    done

    if [[ ${#added[@]} -gt 0 ]]; then
        vokun::core::success "Added ${#added[@]} package(s) to '$bundle_name': ${added[*]}"
    fi
}

# --- vokun bundle rm ---

vokun::bundle_mgmt::rm() {
    local bundle_name="${1:-}"
    shift 2>/dev/null || true

    if [[ -z "$bundle_name" || $# -eq 0 ]]; then
        vokun::core::error "Usage: vokun bundle rm <bundle> <pkg> [pkg...]"
        return 1
    fi

    local file
    file=$(vokun::bundles::find_by_name "$bundle_name") || {
        vokun::core::error "Bundle not found: $bundle_name"
        return 1
    }

    # Never modify system defaults — copy to custom first
    if vokun::bundle_mgmt::_is_default_bundle "$file"; then
        file=$(vokun::bundle_mgmt::_copy_to_custom "$file")
    fi

    local -a removed=()
    local pkg
    for pkg in "$@"; do
        if grep -q "^${pkg}[[:space:]]*=" "$file"; then
            sed -i "/^${pkg}[[:space:]]*=/d" "$file"
            removed+=("$pkg")
        else
            vokun::core::warn "Package '$pkg' not found in bundle '$bundle_name'"
        fi
    done

    if [[ ${#removed[@]} -gt 0 ]]; then
        vokun::core::success "Removed ${#removed[@]} package(s) from '$bundle_name': ${removed[*]}"
    fi
}

# --- vokun bundle edit ---

vokun::bundle_mgmt::edit() {
    local bundle_name="${1:-}"

    if [[ -z "$bundle_name" ]]; then
        vokun::core::error "Usage: vokun bundle edit <bundle>"
        return 1
    fi

    local file
    file=$(vokun::bundles::find_by_name "$bundle_name") || {
        vokun::core::error "Bundle not found: $bundle_name"
        return 1
    }

    # Never modify system defaults — copy to custom first
    if vokun::bundle_mgmt::_is_default_bundle "$file"; then
        file=$(vokun::bundle_mgmt::_copy_to_custom "$file")
    fi

    if command -v fzf &>/dev/null && [[ "${VOKUN_FZF:-true}" == "true" ]]; then
        # Parse current bundle packages
        vokun::toml::parse "$file"
        local pkg_keys
        pkg_keys=$(vokun::toml::keys "packages")

        # Build list of all available packages, pre-selecting current ones
        local -a current_pkgs=()
        if [[ -n "$pkg_keys" ]]; then
            while IFS= read -r pkg; do
                [[ -z "$pkg" ]] && continue
                current_pkgs+=("$pkg")
            done <<< "$pkg_keys"
        fi

        vokun::core::info "Toggle packages with TAB, confirm with ENTER"

        # Build fzf input: all available packages from pacman
        local -a selected
        mapfile -t selected < <(
            pacman -Slq 2>/dev/null | awk -v current="${current_pkgs[*]}" '
                BEGIN { split(current, arr, " "); for (i in arr) pkgs[arr[i]]=1 }
                { print $0 }
            ' | fzf --multi --prompt="Edit ${bundle_name}> " \
                     --preview="pacman -Si {1} 2>/dev/null" \
                     --header="Current packages are listed. TAB to toggle." \
                     --bind="ctrl-a:select-all,ctrl-d:deselect-all" \
                     2>/dev/null || true
        )

        if [[ ${#selected[@]} -eq 0 && ${#current_pkgs[@]} -gt 0 ]]; then
            vokun::core::warn "No packages selected (fzf cancelled). Bundle unchanged."
            return 0
        fi

        # Rebuild the TOML file: preserve [meta] section, rewrite [packages]
        local tmp
        tmp=$(mktemp)

        # Copy everything up to (but not including) [packages]
        awk '/^\[packages\]/ { exit } { print }' "$file" > "$tmp"

        # Write new [packages] section
        printf '[packages]\n' >> "$tmp"
        for pkg in "${selected[@]}"; do
            [[ -z "$pkg" ]] && continue
            local desc
            desc=$(vokun::bundle_mgmt::_pkg_description "$pkg")
            printf '%s = "%s"\n' "$pkg" "$desc" >> "$tmp"
        done

        # Copy sections after [packages] (e.g. [packages.aur], [packages.optional], [hooks])
        local after_packages
        after_packages=$(awk '
            BEGIN { in_pkg=0; past_pkg=0 }
            /^\[packages\]/ { in_pkg=1; next }
            in_pkg && /^\[/ && !/^\[packages\]/ { in_pkg=0; past_pkg=1 }
            past_pkg { print }
        ' "$file")
        if [[ -n "$after_packages" ]]; then
            printf '\n%s\n' "$after_packages" >> "$tmp"
        fi

        mv "$tmp" "$file"
        vokun::core::success "Updated bundle '$bundle_name' with ${#selected[@]} package(s)"
    else
        # Fall back to $EDITOR
        local editor="${EDITOR:-nano}"
        vokun::core::info "Opening '$file' in $editor"
        vokun::core::show_cmd "$editor $file"
        "$editor" "$file"
    fi
}

# --- vokun bundle delete ---

vokun::bundle_mgmt::delete() {
    local name="${1:-}"

    if [[ -z "$name" ]]; then
        vokun::core::error "Usage: vokun bundle delete <name>"
        return 1
    fi

    local custom_file="${VOKUN_CONFIG_DIR}/bundles/custom/${name}.toml"

    # Only allow deleting custom bundles
    if [[ ! -f "$custom_file" ]]; then
        # Check if it's a default bundle
        if [[ -n "$VOKUN_SYSTEM_BUNDLE_DIR" && -f "${VOKUN_SYSTEM_BUNDLE_DIR}/${name}.toml" ]]; then
            vokun::core::error "Cannot delete default bundle '$name'"
            vokun::core::log "Default bundles are managed by the system package."
            return 1
        fi
        vokun::core::error "Custom bundle not found: $name"
        return 1
    fi

    # Confirm deletion
    if ! vokun::core::confirm "Delete custom bundle '$name'?"; then
        vokun::core::log "Deletion cancelled."
        return 0
    fi

    rm "$custom_file"

    # Remove from state if installed
    if vokun::state::is_installed "$name"; then
        vokun::state::remove_bundle "$name"
        vokun::core::info "Removed '$name' from installed state"
    fi

    vokun::core::success "Deleted bundle '$name'"
}
