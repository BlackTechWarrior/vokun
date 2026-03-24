#!/usr/bin/env bash
# shellcheck disable=SC2034
# vokun - Sync command
# Bridges the gap between vokun bundle management and direct pacman/paru usage.
# Finds explicitly installed packages that are not tracked in any bundle.

# --- Unmanaged package helpers ---

# Get the list of packages marked as unmanaged in state.json
vokun::sync::get_unmanaged() {
    if ! command -v jq &>/dev/null; then
        return
    fi

    jq -r '.unmanaged[]? // empty' "$VOKUN_STATE_FILE" 2>/dev/null
}

# Mark packages as unmanaged (ignored) in state.json
# Usage: vokun::sync::mark_unmanaged pkg1 pkg2 ...
vokun::sync::mark_unmanaged() {
    if [[ $# -eq 0 ]]; then
        vokun::core::error "No packages specified"
        return 1
    fi

    if ! command -v jq &>/dev/null; then
        vokun::core::warn "jq not available — cannot update state"
        return 1
    fi

    # Build a JSON array from the arguments
    local pkg_json
    # shellcheck disable=SC2086
    pkg_json=$(printf '%s\n' "$@" | jq -R . | jq -s .)

    local tmp
    tmp=$(mktemp)
    jq --argjson pkgs "$pkg_json" \
       '.unmanaged = (.unmanaged + $pkgs | unique)' \
       "$VOKUN_STATE_FILE" > "$tmp" && mv "$tmp" "$VOKUN_STATE_FILE"

    vokun::core::success "Marked ${#} package(s) as unmanaged"
}

# --- Categorization ---

# Build a lookup of foreign (AUR) packages — one call instead of per-package
declare -gA _VOKUN_FOREIGN_PKGS=()
vokun::sync::_build_foreign_cache() {
    _VOKUN_FOREIGN_PKGS=()
    local pkg
    while IFS= read -r pkg; do
        pkg="${pkg%% *}"
        [[ -n "$pkg" ]] && _VOKUN_FOREIGN_PKGS["$pkg"]=1
    done < <(pacman -Qmq 2>/dev/null || true)
}

# Categorize a package as "aur" or "repo"
vokun::sync::get_pkg_repo() {
    local pkg="$1"
    if [[ -v "_VOKUN_FOREIGN_PKGS[$pkg]" ]]; then
        printf 'aur'
    else
        printf 'repo'
    fi
}

# --- Main sync command ---

vokun::sync::run() {
    local auto_mode=false
    local quiet_mode=false

    for arg in "$@"; do
        case "$arg" in
            --auto) auto_mode=true ;;
            --quiet) quiet_mode=true; auto_mode=true ;;
        esac
    done

    if ! command -v jq &>/dev/null; then
        vokun::core::error "jq is required for the sync command"
        vokun::core::log "Install it with: sudo pacman -S jq"
        return 1
    fi

    vokun::core::info "Scanning for untracked packages..."

    # Get all explicitly installed packages
    vokun::core::show_cmd "pacman -Qeq"
    local -a explicit_pkgs
    mapfile -t explicit_pkgs < <(pacman -Qeq)

    # Get all packages tracked in bundles
    local -a tracked_pkgs
    mapfile -t tracked_pkgs < <(vokun::state::get_all_tracked_packages)

    # Get packages marked as unmanaged
    local -a unmanaged_pkgs
    mapfile -t unmanaged_pkgs < <(vokun::sync::get_unmanaged)

    # Find untracked packages using associative array lookups (fast)
    local -A known_pkgs=()
    local pkg
    for pkg in "${tracked_pkgs[@]}"; do
        [[ -n "$pkg" ]] && known_pkgs["$pkg"]=1
    done
    for pkg in "${unmanaged_pkgs[@]}"; do
        [[ -n "$pkg" ]] && known_pkgs["$pkg"]=1
    done

    # Build a fast lookup of what's actually installed on the system
    local -A installed_pkgs=()
    for pkg in "${explicit_pkgs[@]}"; do
        [[ -n "$pkg" ]] && installed_pkgs["$pkg"]=1
    done
    # Also include dependency-installed packages (not just explicit)
    local dep_pkg
    while IFS= read -r dep_pkg; do
        [[ -n "$dep_pkg" ]] && installed_pkgs["$dep_pkg"]=1
    done < <(pacman -Qqd 2>/dev/null || true)

    # Forward sync: find packages installed but not in any bundle
    local -a untracked=()
    for pkg in "${explicit_pkgs[@]}"; do
        [[ -z "$pkg" ]] && continue
        if [[ ! -v "known_pkgs[$pkg]" ]]; then
            untracked+=("$pkg")
        fi
    done

    # Reverse sync: find packages tracked in bundles but no longer installed
    local -a missing_from_system=()
    local -A missing_by_bundle=()
    local -a bundle_names
    mapfile -t bundle_names < <(vokun::state::get_installed_bundles)

    for bundle in "${bundle_names[@]}"; do
        [[ -z "$bundle" ]] && continue
        local -a bpkgs
        mapfile -t bpkgs < <(vokun::state::get_bundle_packages "$bundle")
        for pkg in "${bpkgs[@]}"; do
            [[ -z "$pkg" ]] && continue
            if [[ ! -v "installed_pkgs[$pkg]" ]]; then
                missing_from_system+=("$pkg")
                if [[ -v "missing_by_bundle[$bundle]" ]]; then
                    missing_by_bundle["$bundle"]+=" $pkg"
                else
                    missing_by_bundle["$bundle"]="$pkg"
                fi
            fi
        done
    done

    # Quiet mode: just print counts and exit
    if [[ "$quiet_mode" == true ]]; then
        local issues=0
        [[ ${#untracked[@]} -gt 0 ]] && issues=$((issues + ${#untracked[@]}))
        [[ ${#missing_from_system[@]} -gt 0 ]] && issues=$((issues + ${#missing_from_system[@]}))
        if [[ $issues -gt 0 ]]; then
            printf 'vokun: %d sync issue(s). Run '\''vokun sync'\'' to review.\n' "$issues"
        fi
        return 0
    fi

    # Report
    printf '\n'
    printf '%s Sync Summary%s\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET"
    printf '%s\n' "$(printf '%.0s─' {1..50})"
    printf '  Explicitly installed:  %d\n' "${#explicit_pkgs[@]}"
    printf '  Tracked in bundles:    %d\n' "${#tracked_pkgs[@]}"
    printf '  Marked as unmanaged:   %d\n' "${#unmanaged_pkgs[@]}"
    printf '  %sUntracked:             %d%s\n' "$VOKUN_COLOR_YELLOW" "${#untracked[@]}" "$VOKUN_COLOR_RESET"
    printf '  %sMissing from system:   %d%s\n' "$VOKUN_COLOR_RED" "${#missing_from_system[@]}" "$VOKUN_COLOR_RESET"

    # Show missing packages (reverse sync)
    if [[ ${#missing_from_system[@]} -gt 0 ]]; then
        printf '\n  %sPackages tracked by vokun but no longer installed:%s\n' "$VOKUN_COLOR_RED" "$VOKUN_COLOR_RESET"
        for bundle in "${!missing_by_bundle[@]}"; do
            printf '\n    %s[%s]%s\n' "$VOKUN_COLOR_MAGENTA" "$bundle" "$VOKUN_COLOR_RESET"
            # shellcheck disable=SC2086
            for pkg in ${missing_by_bundle[$bundle]}; do
                printf '      %s\n' "$pkg"
            done
        done

        if [[ "$auto_mode" == false ]]; then
            printf '\n'
            printf '  %sOptions:%s\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET"
            printf '    %s1)%s Reinstall missing packages\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET"
            printf '    %s2)%s Remove them from bundle tracking\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET"
            printf '    %s3)%s Skip\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET"
            printf '\n  Choice [1-3]: '
            local missing_choice
            read -r missing_choice
            case "$missing_choice" in
                1)
                    vokun::core::run_pacman "-S" "--needed" "${missing_from_system[@]}"
                    ;;
                2)
                    vokun::sync::_remove_missing_from_state "${bundle_names[@]}"
                    ;;
            esac
        fi
        printf '\n'
    fi

    # Bundle drift detection
    vokun::sync::check_drift "$auto_mode"

    if [[ ${#untracked[@]} -eq 0 && ${#missing_from_system[@]} -eq 0 ]]; then
        printf '\n'
        vokun::core::success "Everything is in sync!"
        return 0
    fi

    if [[ ${#untracked[@]} -eq 0 ]]; then
        return 0
    fi

    # Group untracked packages by repository
    printf '\n  %sUntracked packages:%s\n' "$VOKUN_COLOR_YELLOW" "$VOKUN_COLOR_RESET"

    vokun::sync::_build_foreign_cache
    declare -A repo_groups
    for pkg in "${untracked[@]}"; do
        local repo
        repo=$(vokun::sync::get_pkg_repo "$pkg")
        if [[ -v "repo_groups[$repo]" ]]; then
            repo_groups["$repo"]+=" $pkg"
        else
            repo_groups["$repo"]="$pkg"
        fi
    done

    for repo in $(printf '%s\n' "${!repo_groups[@]}" | sort); do
        printf '\n    %s[%s]%s\n' "$VOKUN_COLOR_MAGENTA" "$repo" "$VOKUN_COLOR_RESET"
        local pkg_list
        # shellcheck disable=SC2086
        for pkg in ${repo_groups[$repo]}; do
            printf '      %s\n' "$pkg"
        done
    done

    printf '\n'

    # In auto mode, just list and exit
    if [[ "$auto_mode" == true ]]; then
        return 0
    fi

    # Interactive loop — let users sort packages in batches
    local -a remaining=("${untracked[@]}")

    while [[ ${#remaining[@]} -gt 0 ]]; do
        printf '%s\n' "$(printf '%.0s─' {1..50})"
        printf '\n  %s%d untracked package(s) remaining.%s\n\n' \
            "$VOKUN_COLOR_BOLD" "${#remaining[@]}" "$VOKUN_COLOR_RESET"
        printf '    %s1)%s Pick packages to add to a bundle\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET"
        printf '    %s2)%s Pick packages for a new bundle\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET"
        printf '    %s3)%s Mark all remaining as unmanaged (ignore)\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET"
        printf '    %s4)%s Done (skip remaining)\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET"
        printf '\n'

        printf '  Choice [1-4]: '
        local choice
        read -r choice

        case "$choice" in
            1)
                local -a picked=()
                vokun::sync::_pick_packages picked "${remaining[@]}"
                if [[ ${#picked[@]} -gt 0 ]]; then
                    vokun::sync::_prompt_add_to_bundle "${picked[@]}"
                    vokun::sync::_remove_from_list remaining "${picked[@]}"
                fi
                ;;
            2)
                local -a picked=()
                vokun::sync::_pick_packages picked "${remaining[@]}"
                if [[ ${#picked[@]} -gt 0 ]]; then
                    vokun::sync::_prompt_create_bundle "${picked[@]}"
                    vokun::sync::_remove_from_list remaining "${picked[@]}"
                fi
                ;;
            3)
                vokun::sync::mark_unmanaged "${remaining[@]}"
                remaining=()
                ;;
            4|"")
                vokun::core::log "Skipped."
                break
                ;;
            *)
                vokun::core::warn "Invalid choice: $choice"
                ;;
        esac
    done
}

# Let user pick packages from a list (fzf or numbered)
# Usage: vokun::sync::_pick_packages result_array_name "${packages[@]}"
vokun::sync::_pick_packages() {
    local -n _picked="$1"
    shift
    local -a available=("$@")
    _picked=()

    if command -v fzf &>/dev/null && [[ "${VOKUN_FZF:-true}" == "true" ]]; then
        mapfile -t _picked < <(
            printf '%s\n' "${available[@]}" | fzf --multi \
                --header="TAB to select, ENTER to confirm" \
                --prompt="Pick packages> " \
                --no-info 2>/dev/null
        ) || true
    else
        printf '\n  %sSelect packages (space-separated numbers):%s\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET"
        local i=1
        for pkg in "${available[@]}"; do
            printf '    %s%d)%s %s\n' "$VOKUN_COLOR_BOLD" "$i" "$VOKUN_COLOR_RESET" "$pkg"
            ((i++))
        done
        printf '\n  > '
        local selection
        read -r selection
        # shellcheck disable=SC2086
        for num in $selection; do
            if [[ "$num" =~ ^[0-9]+$ ]] && (( num >= 1 && num <= ${#available[@]} )); then
                _picked+=("${available[$((num - 1))]}")
            fi
        done
    fi
}

# Remove picked packages from a remaining list
# Usage: vokun::sync::_remove_from_list remaining_array_name "${picked[@]}"
vokun::sync::_remove_from_list() {
    local -n _remaining="$1"
    shift
    local -a to_remove=("$@")
    local -a new_remaining=()
    local pkg
    for pkg in "${_remaining[@]}"; do
        if ! vokun::core::in_array "$pkg" "${to_remove[@]}"; then
            new_remaining+=("$pkg")
        fi
    done
    _remaining=("${new_remaining[@]}")
}

# Create a new bundle from picked packages
vokun::sync::_prompt_create_bundle() {
    local -a packages=("$@")

    printf '\n  Bundle name: '
    local bundle_name
    read -r bundle_name

    if [[ -z "$bundle_name" ]]; then
        vokun::core::warn "No name given. Skipped."
        return
    fi

    # Create the bundle file
    local custom_dir="${VOKUN_CONFIG_DIR}/bundles/custom"
    mkdir -p "$custom_dir"
    local bundle_file="${custom_dir}/${bundle_name}.toml"

    if [[ -f "$bundle_file" ]]; then
        vokun::core::warn "Bundle '$bundle_name' already exists. Adding packages to it."
    else
        cat > "$bundle_file" <<EOF
[meta]
name = "$bundle_name"
description = "Custom bundle created via vokun sync"
tags = ["custom"]
version = "1.0.0"

[packages]
EOF
    fi

    # Append packages
    local pkg
    for pkg in "${packages[@]}"; do
        local desc
        desc=$(pacman -Qi "$pkg" 2>/dev/null | sed -n 's/^Description *: *//p' || echo "")
        printf '%s = "%s"\n' "$pkg" "$desc" >> "$bundle_file"
    done

    # Track in state
    local pkg_list
    pkg_list=$(printf '%s ' "${packages[@]}")
    vokun::state::add_bundle "$bundle_name" "$pkg_list" "" "custom"

    vokun::core::success "Created bundle '$bundle_name' with ${#packages[@]} package(s)."
    vokun::core::log "  Edit: vokun bundle edit $bundle_name"
}

# Prompt user to select a bundle and show which packages to add
vokun::sync::_prompt_add_to_bundle() {
    local -a packages=("$@")

    # Get installed bundles + available bundles
    local -a bundles
    mapfile -t bundles < <(vokun::state::get_installed_bundles)

    # Also show available (not installed) bundles
    local -a available_bundles=()
    local -a all_files
    mapfile -t all_files < <(vokun::bundles::find_all)
    for f in "${all_files[@]}"; do
        local bname
        bname=$(vokun::bundles::name_from_path "$f")
        if ! vokun::core::in_array "$bname" "${bundles[@]+"${bundles[@]}"}"; then
            available_bundles+=("$bname")
        fi
    done

    local -a all_bundles=("${bundles[@]}" "${available_bundles[@]}")

    if [[ ${#all_bundles[@]} -eq 0 ]]; then
        vokun::core::warn "No bundles found"
        vokun::core::log "Create one first with: vokun bundle create <name>"
        return 1
    fi

    printf '\n  %sBundles:%s\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET"
    local i=1
    for bundle in "${all_bundles[@]}"; do
        local marker=""
        if vokun::state::is_installed "$bundle"; then
            marker=" ${VOKUN_COLOR_GREEN}[installed]${VOKUN_COLOR_RESET}"
        fi
        printf '    %s%d)%s %s%s\n' "$VOKUN_COLOR_BOLD" "$i" "$VOKUN_COLOR_RESET" "$bundle" "$marker"
        ((i++))
    done

    printf '\n  Select a bundle [1-%d]: ' "${#all_bundles[@]}"
    local bundle_choice
    read -r bundle_choice

    # Validate
    if ! [[ "$bundle_choice" =~ ^[0-9]+$ ]] || [[ "$bundle_choice" -lt 1 ]] || [[ "$bundle_choice" -gt ${#all_bundles[@]} ]]; then
        vokun::core::warn "Invalid selection"
        return
    fi

    local selected_bundle="${all_bundles[$((bundle_choice - 1))]}"

    # Add packages to state tracking
    local current_pkgs=""
    if vokun::state::is_installed "$selected_bundle"; then
        current_pkgs=$(vokun::state::get_bundle_packages "$selected_bundle" | tr '\n' ' ')
    fi
    local new_pkgs
    new_pkgs=$(printf '%s ' "${packages[@]}")
    vokun::state::add_bundle "$selected_bundle" "${current_pkgs}${new_pkgs}" "" "default"

    vokun::core::success "Added ${#packages[@]} package(s) to '$selected_bundle'."
}

# Remove missing packages from bundle state
# Rewrites each bundle's package list to only include what's actually installed
vokun::sync::_remove_missing_from_state() {
    if ! command -v jq &>/dev/null; then
        vokun::core::warn "jq not available"
        return 1
    fi

    local -A installed_check=()
    local p
    while IFS= read -r p; do
        [[ -n "$p" ]] && installed_check["$p"]=1
    done < <(pacman -Qq 2>/dev/null)

    local bundle
    for bundle in "$@"; do
        [[ -z "$bundle" ]] && continue
        local -a current_pkgs
        mapfile -t current_pkgs < <(vokun::state::get_bundle_packages "$bundle")

        local -a keep=()
        local -a removed=()
        for p in "${current_pkgs[@]}"; do
            [[ -z "$p" ]] && continue
            if [[ -v "installed_check[$p]" ]]; then
                keep+=("$p")
            else
                removed+=("$p")
            fi
        done

        if [[ ${#removed[@]} -gt 0 ]]; then
            # Update the bundle's package list in state
            local pkg_json
            pkg_json=$(printf '%s\n' "${keep[@]}" | jq -R . | jq -s .)
            local tmp
            tmp=$(mktemp)
            jq --arg b "$bundle" --argjson pkgs "$pkg_json" \
                '.installed_bundles[$b].packages = $pkgs' \
                "$VOKUN_STATE_FILE" > "$tmp" && mv "$tmp" "$VOKUN_STATE_FILE"
            vokun::core::success "Removed ${#removed[@]} missing package(s) from '$bundle': ${removed[*]}"
        fi
    done
}

# --- Bundle drift detection ---
# Compare installed bundles' state against current TOML definitions
# Finds packages added or removed upstream since the bundle was installed

vokun::sync::check_drift() {
    local auto_mode="${1:-false}"

    local -a bundle_names
    mapfile -t bundle_names < <(vokun::state::get_installed_bundles)

    if [[ ${#bundle_names[@]} -eq 0 ]]; then
        return
    fi

    local has_drift=false
    local -A bundles_with_new=()
    local -A bundles_with_removed=()

    for bundle in "${bundle_names[@]}"; do
        [[ -z "$bundle" ]] && continue

        # Get what's in state
        local -a state_pkgs
        mapfile -t state_pkgs < <(vokun::state::get_bundle_packages "$bundle")
        local -A state_set=()
        for p in "${state_pkgs[@]}"; do
            [[ -n "$p" ]] && state_set["$p"]=1
        done

        # Get skipped packages from state too — don't flag those as "new"
        local -A skipped_set=()
        local skipped_raw
        skipped_raw=$(jq -r --arg b "$bundle" '.installed_bundles[$b].skipped[]? // empty' "$VOKUN_STATE_FILE" 2>/dev/null || true)
        while IFS= read -r p; do
            [[ -n "$p" ]] && skipped_set["$p"]=1
        done <<< "$skipped_raw"

        # Find the current TOML definition
        local file
        file=$(vokun::bundles::find_by_name "$bundle" 2>/dev/null) || continue

        # Parse the TOML and get all defined packages
        vokun::toml::parse "$file"
        local -A toml_set=()
        local keys
        keys=$(vokun::toml::keys "packages")
        while IFS= read -r p; do
            [[ -n "$p" ]] && toml_set["$p"]=1
        done <<< "$keys"
        keys=$(vokun::toml::keys "packages.aur")
        while IFS= read -r p; do
            [[ -n "$p" ]] && toml_set["$p"]=1
        done <<< "$keys"

        # Find new packages (in TOML but not in state and not skipped)
        local -a new_pkgs=()
        for p in "${!toml_set[@]}"; do
            if [[ ! -v "state_set[$p]" && ! -v "skipped_set[$p]" ]]; then
                new_pkgs+=("$p")
            fi
        done

        # Find removed packages (in state but not in TOML)
        local -a removed_pkgs=()
        for p in "${!state_set[@]}"; do
            if [[ ! -v "toml_set[$p]" ]]; then
                removed_pkgs+=("$p")
            fi
        done

        if [[ ${#new_pkgs[@]} -gt 0 ]]; then
            has_drift=true
            bundles_with_new["$bundle"]="${new_pkgs[*]}"
        fi
        if [[ ${#removed_pkgs[@]} -gt 0 ]]; then
            has_drift=true
            bundles_with_removed["$bundle"]="${removed_pkgs[*]}"
        fi
    done

    if [[ "$has_drift" == false ]]; then
        return
    fi

    printf '\n  %sBundle definition changes detected:%s\n' "$VOKUN_COLOR_CYAN" "$VOKUN_COLOR_RESET"

    for bundle in "${!bundles_with_new[@]}"; do
        printf '\n    %s[%s]%s new packages available:\n' "$VOKUN_COLOR_MAGENTA" "$bundle" "$VOKUN_COLOR_RESET"
        # shellcheck disable=SC2086
        for p in ${bundles_with_new[$bundle]}; do
            printf '      %s+ %s%s\n' "$VOKUN_COLOR_GREEN" "$p" "$VOKUN_COLOR_RESET"
        done
    done

    for bundle in "${!bundles_with_removed[@]}"; do
        printf '\n    %s[%s]%s packages removed from definition:\n' "$VOKUN_COLOR_MAGENTA" "$bundle" "$VOKUN_COLOR_RESET"
        # shellcheck disable=SC2086
        for p in ${bundles_with_removed[$bundle]}; do
            printf '      %s- %s%s\n' "$VOKUN_COLOR_RED" "$p" "$VOKUN_COLOR_RESET"
        done
    done

    if [[ "$auto_mode" == true ]]; then
        return
    fi

    # Offer to update
    if [[ ${#bundles_with_new[@]} -gt 0 ]]; then
        printf '\n'
        if vokun::core::confirm "Install new packages from updated bundles?"; then
            for bundle in "${!bundles_with_new[@]}"; do
                local -a new_list
                # shellcheck disable=SC2086
                read -ra new_list <<< "${bundles_with_new[$bundle]}"
                vokun::core::run_pacman "-S" "--needed" "${new_list[@]}"
                # Update state with the new packages
                local current_pkgs
                current_pkgs=$(vokun::state::get_bundle_packages "$bundle" | tr '\n' ' ')
                vokun::state::add_bundle "$bundle" "${current_pkgs}${new_list[*]} " "" "default"
            done
        fi
    fi

    if [[ ${#bundles_with_removed[@]} -gt 0 ]]; then
        printf '\n'
        if vokun::core::confirm "Remove packages dropped from bundle definitions?"; then
            for bundle in "${!bundles_with_removed[@]}"; do
                local -a rm_list
                # shellcheck disable=SC2086
                read -ra rm_list <<< "${bundles_with_removed[$bundle]}"
                # Only remove if not in another bundle
                local -a safe_to_remove=()
                for p in "${rm_list[@]}"; do
                    local shared
                    shared=$(vokun::state::get_shared_packages "$bundle" "$p")
                    if [[ -z "$shared" ]]; then
                        safe_to_remove+=("$p")
                    fi
                done
                if [[ ${#safe_to_remove[@]} -gt 0 ]]; then
                    vokun::core::run_pacman_only "-Rns" "${safe_to_remove[@]}"
                fi
                # Update state
                local -a kept=()
                local -a current
                mapfile -t current < <(vokun::state::get_bundle_packages "$bundle")
                for p in "${current[@]}"; do
                    [[ -z "$p" ]] && continue
                    if ! vokun::core::in_array "$p" "${rm_list[@]}"; then
                        kept+=("$p")
                    fi
                done
                local kept_str
                kept_str=$(printf '%s ' "${kept[@]}")
                vokun::state::add_bundle "$bundle" "$kept_str" "" "default"
            done
        fi
    fi
}
