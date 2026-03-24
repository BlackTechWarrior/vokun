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

    # Interactive prompts
    printf '%s\n' "$(printf '%.0s─' {1..50})"
    printf '\n  What would you like to do with these packages?\n\n'
    printf '    %s1)%s Add to an existing bundle\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET"
    printf '    %s2)%s Create a new bundle for them\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET"
    printf '    %s3)%s Mark all as unmanaged (ignore)\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET"
    printf '    %s4)%s Skip (do nothing)\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET"
    printf '\n'

    printf '  Choice [1-4]: '
    local choice
    read -r choice

    case "$choice" in
        1)
            vokun::sync::_prompt_add_to_bundle "${untracked[@]}"
            ;;
        2)
            printf '\n'
            vokun::core::info "Create a new bundle with:"
            vokun::core::log "  vokun bundle create <name>"
            vokun::core::log ""
            vokun::core::log "Then add the packages to its TOML file and run:"
            vokun::core::log "  vokun install <name>"
            ;;
        3)
            printf '\n'
            vokun::sync::mark_unmanaged "${untracked[@]}"
            ;;
        4|"")
            vokun::core::log "Skipped."
            ;;
        *)
            vokun::core::error "Invalid choice: $choice"
            return 1
            ;;
    esac
}

# Prompt user to select a bundle and show which packages to add
vokun::sync::_prompt_add_to_bundle() {
    local -a packages=("$@")

    # Get installed bundles
    local -a bundles
    mapfile -t bundles < <(vokun::state::get_installed_bundles)

    if [[ ${#bundles[@]} -eq 0 ]]; then
        vokun::core::warn "No installed bundles found"
        vokun::core::log "Create one first with: vokun bundle create <name>"
        return 1
    fi

    printf '\n  %sInstalled bundles:%s\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET"
    local i=1
    for bundle in "${bundles[@]}"; do
        printf '    %s%d)%s %s\n' "$VOKUN_COLOR_BOLD" "$i" "$VOKUN_COLOR_RESET" "$bundle"
        ((i++))
    done

    printf '\n  Select a bundle [1-%d]: ' "${#bundles[@]}"
    local bundle_choice
    read -r bundle_choice

    # Validate
    if ! [[ "$bundle_choice" =~ ^[0-9]+$ ]] || [[ "$bundle_choice" -lt 1 ]] || [[ "$bundle_choice" -gt ${#bundles[@]} ]]; then
        vokun::core::error "Invalid selection"
        return 1
    fi

    local selected_bundle="${bundles[$((bundle_choice - 1))]}"

    printf '\n'
    vokun::core::info "To add these packages to '$selected_bundle', add them to the bundle's TOML file:"

    local bundle_file
    bundle_file=$(vokun::bundles::find_by_name "$selected_bundle" 2>/dev/null) || bundle_file=""

    if [[ -n "$bundle_file" ]]; then
        vokun::core::log "  $bundle_file"
    fi

    printf '\n  %sPackages to add:%s\n' "$VOKUN_COLOR_GREEN" "$VOKUN_COLOR_RESET"
    for pkg in "${packages[@]}"; do
        printf '    %s = ""\n' "$pkg"
    done

    printf '\n  After editing, re-install the bundle to update tracking:\n'
    vokun::core::log "  vokun install $selected_bundle"
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
