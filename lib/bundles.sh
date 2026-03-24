#!/usr/bin/env bash
# vokun - Bundle operations
# list, info, search, install, remove

# --- Bundle discovery ---

# Find all bundle TOML files (system defaults + custom)
# Returns full paths, one per line
vokun::bundles::find_all() {
    local -a dirs=()

    [[ -n "$VOKUN_SYSTEM_BUNDLE_DIR" && -d "$VOKUN_SYSTEM_BUNDLE_DIR" ]] && dirs+=("$VOKUN_SYSTEM_BUNDLE_DIR")
    [[ -d "${VOKUN_CONFIG_DIR}/bundles/custom" ]] && dirs+=("${VOKUN_CONFIG_DIR}/bundles/custom")

    for dir in "${dirs[@]}"; do
        local f
        for f in "$dir"/*.toml; do
            [[ -f "$f" ]] && printf '%s\n' "$f"
        done
    done
}

# Get bundle name from file path (filename without .toml)
vokun::bundles::name_from_path() {
    local path="$1"
    local basename
    basename=$(basename "$path")
    printf '%s' "${basename%.toml}"
}

# Find a bundle file by name
# Returns the path, or empty string if not found
vokun::bundles::find_by_name() {
    local name="$1"

    # Check system bundles first
    if [[ -n "$VOKUN_SYSTEM_BUNDLE_DIR" && -f "${VOKUN_SYSTEM_BUNDLE_DIR}/${name}.toml" ]]; then
        printf '%s' "${VOKUN_SYSTEM_BUNDLE_DIR}/${name}.toml"
        return
    fi

    # Check custom bundles
    if [[ -f "${VOKUN_CONFIG_DIR}/bundles/custom/${name}.toml" ]]; then
        printf '%s' "${VOKUN_CONFIG_DIR}/bundles/custom/${name}.toml"
        return
    fi

    return 1
}

# --- vokun list ---

vokun::bundles::list() {
    local show_installed_only=false
    local names_only=false

    for arg in "$@"; do
        case "$arg" in
            --installed) show_installed_only=true ;;
            --names-only) names_only=true ;;
        esac
    done

    local -a bundle_files
    mapfile -t bundle_files < <(vokun::bundles::find_all)

    if [[ ${#bundle_files[@]} -eq 0 ]]; then
        vokun::core::warn "No bundles found"
        return 1
    fi

    # If just listing names (for completions)
    if [[ "$names_only" == true ]]; then
        for file in "${bundle_files[@]}"; do
            vokun::bundles::name_from_path "$file"
            printf '\n'
        done
        return
    fi

    # Collect bundle metadata, grouped by first tag
    declare -A tag_bundles  # tag -> newline-separated "name|description|installed"

    for file in "${bundle_files[@]}"; do
        vokun::toml::parse "$file"

        local name description tags_str
        name=$(vokun::bundles::name_from_path "$file")
        description=$(vokun::toml::get "meta.description" "No description")
        tags_str=$(vokun::toml::get "meta.tags" "")

        local installed=""
        if vokun::state::is_installed "$name"; then
            installed="yes"
        elif [[ "$show_installed_only" == true ]]; then
            continue
        fi

        # Get first tag as category
        local category="other"
        if [[ -n "$tags_str" ]]; then
            # tags_str is newline-separated from array parsing
            category=$(echo "$tags_str" | head -1)
        fi

        local entry="${name}|${description}|${installed}"
        if [[ -v "tag_bundles[$category]" ]]; then
            tag_bundles["$category"]+=$'\n'"$entry"
        else
            tag_bundles["$category"]="$entry"
        fi
    done

    # Display
    printf '\n'
    printf '%s Available Bundles%s\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET"
    printf '%s\n' "$(printf '%.0s─' {1..50})"

    local category
    for category in $(printf '%s\n' "${!tag_bundles[@]}" | sort); do
        printf '\n  %s[%s]%s\n' "$VOKUN_COLOR_MAGENTA" "$category" "$VOKUN_COLOR_RESET"

        while IFS='|' read -r name description installed; do
            [[ -z "$name" ]] && continue
            local status_icon=""
            if [[ "$installed" == "yes" ]]; then
                status_icon="${VOKUN_COLOR_GREEN} [installed]${VOKUN_COLOR_RESET}"
            fi
            printf '    %s%-20s%s %s%s\n' "$VOKUN_COLOR_BOLD" "$name" "$VOKUN_COLOR_RESET" "$description" "$status_icon"
        done <<< "${tag_bundles[$category]}"
    done

    printf '\n%sRun %svokun info <bundle>%s for details%s\n\n' \
        "$VOKUN_COLOR_DIM" "$VOKUN_COLOR_RESET${VOKUN_COLOR_BOLD}" "$VOKUN_COLOR_RESET${VOKUN_COLOR_DIM}" "$VOKUN_COLOR_RESET"
}

# --- vokun info ---

vokun::bundles::info() {
    local name="${1:-}"

    if [[ -z "$name" ]]; then
        vokun::core::error "Usage: vokun info <bundle>"
        return 1
    fi

    local file
    file=$(vokun::bundles::find_by_name "$name") || {
        vokun::core::error "Bundle not found: $name"
        vokun::core::log "Run 'vokun list' to see available bundles."
        return 1
    }

    vokun::toml::parse "$file"

    local description version tags_str
    description=$(vokun::toml::get "meta.description" "No description")
    version=$(vokun::toml::get "meta.version" "")
    tags_str=$(vokun::toml::get "meta.tags" "")

    # Header
    printf '\n'
    printf '%s%s%s' "$VOKUN_COLOR_BOLD" "$name" "$VOKUN_COLOR_RESET"
    [[ -n "$version" ]] && printf ' %s(v%s)%s' "$VOKUN_COLOR_DIM" "$version" "$VOKUN_COLOR_RESET"
    if vokun::state::is_installed "$name"; then
        printf ' %s[installed]%s' "$VOKUN_COLOR_GREEN" "$VOKUN_COLOR_RESET"
    fi
    printf '\n'
    printf '%s\n' "$description"

    if [[ -n "$tags_str" ]]; then
        local tags_display
        tags_display=$(echo "$tags_str" | tr '\n' ', ' | sed 's/,$//')
        printf '%sTags: %s%s\n' "$VOKUN_COLOR_DIM" "$tags_display" "$VOKUN_COLOR_RESET"
    fi

    printf '%s\n' "$(printf '%.0s─' {1..50})"

    # Packages
    local pkg_keys
    pkg_keys=$(vokun::toml::keys "packages")
    if [[ -n "$pkg_keys" ]]; then
        printf '\n  %sPackages:%s\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET"
        while IFS= read -r pkg; do
            [[ -z "$pkg" ]] && continue
            local desc
            desc=$(vokun::toml::get "packages.${pkg}")
            local status=""
            if vokun::core::is_pkg_installed "$pkg"; then
                status="${VOKUN_COLOR_GREEN} [installed]${VOKUN_COLOR_RESET}"
            fi
            printf '    %-25s %s%s\n' "$pkg" "${VOKUN_COLOR_DIM}${desc}${VOKUN_COLOR_RESET}" "$status"
        done <<< "$pkg_keys"
    fi

    # AUR packages
    local aur_keys
    aur_keys=$(vokun::toml::keys "packages.aur")
    if [[ -n "$aur_keys" ]]; then
        printf '\n  %sAUR Packages:%s %s(requires paru/yay)%s\n' \
            "$VOKUN_COLOR_YELLOW" "$VOKUN_COLOR_RESET" "$VOKUN_COLOR_DIM" "$VOKUN_COLOR_RESET"
        while IFS= read -r pkg; do
            [[ -z "$pkg" ]] && continue
            local desc
            desc=$(vokun::toml::get "packages.aur.${pkg}")
            local status=""
            if vokun::core::is_pkg_installed "$pkg"; then
                status="${VOKUN_COLOR_GREEN} [installed]${VOKUN_COLOR_RESET}"
            fi
            printf '    %-25s %s%s\n' "$pkg" "${VOKUN_COLOR_DIM}${desc}${VOKUN_COLOR_RESET}" "$status"
        done <<< "$aur_keys"
    fi

    # Optional packages
    local opt_keys
    opt_keys=$(vokun::toml::keys "packages.optional")
    if [[ -n "$opt_keys" ]]; then
        printf '\n  %sOptional:%s\n' "$VOKUN_COLOR_CYAN" "$VOKUN_COLOR_RESET"
        while IFS= read -r pkg; do
            [[ -z "$pkg" ]] && continue
            local desc
            desc=$(vokun::toml::get "packages.optional.${pkg}")
            local status=""
            if vokun::core::is_pkg_installed "$pkg"; then
                status="${VOKUN_COLOR_GREEN} [installed]${VOKUN_COLOR_RESET}"
            fi
            printf '    %-25s %s%s\n' "$pkg" "${VOKUN_COLOR_DIM}${desc}${VOKUN_COLOR_RESET}" "$status"
        done <<< "$opt_keys"
    fi

    printf '\n'
}

# --- vokun search ---

vokun::bundles::search() {
    local query="${1:-}"

    if [[ -z "$query" ]]; then
        vokun::core::error "Usage: vokun search <keyword>"
        return 1
    fi

    local -a bundle_files
    mapfile -t bundle_files < <(vokun::bundles::find_all)

    local found=false
    local query_lower
    query_lower=$(echo "$query" | tr '[:upper:]' '[:lower:]')

    printf '\n%sSearch results for "%s":%s\n\n' "$VOKUN_COLOR_BOLD" "$query" "$VOKUN_COLOR_RESET"

    for file in "${bundle_files[@]}"; do
        vokun::toml::parse "$file"

        local name description tags_str
        name=$(vokun::bundles::name_from_path "$file")
        description=$(vokun::toml::get "meta.description" "")
        tags_str=$(vokun::toml::get "meta.tags" "")

        local match=false
        local match_reason=""

        # Check name
        if [[ "${name,,}" == *"$query_lower"* ]]; then
            match=true
            match_reason="name"
        fi

        # Check description
        if [[ "${description,,}" == *"$query_lower"* ]]; then
            match=true
            match_reason="${match_reason:+$match_reason, }description"
        fi

        # Check tags
        if [[ "${tags_str,,}" == *"$query_lower"* ]]; then
            match=true
            match_reason="${match_reason:+$match_reason, }tags"
        fi

        # Check package names
        local all_keys=""
        all_keys+=$(vokun::toml::keys "packages")
        all_keys+=$'\n'$(vokun::toml::keys "packages.aur")
        all_keys+=$'\n'$(vokun::toml::keys "packages.optional")

        if [[ "${all_keys,,}" == *"$query_lower"* ]]; then
            match=true
            match_reason="${match_reason:+$match_reason, }packages"
        fi

        if [[ "$match" == true ]]; then
            found=true
            local installed=""
            if vokun::state::is_installed "$name"; then
                installed=" ${VOKUN_COLOR_GREEN}[installed]${VOKUN_COLOR_RESET}"
            fi
            printf '  %s%-20s%s %s %s(matched: %s)%s%s\n' \
                "$VOKUN_COLOR_BOLD" "$name" "$VOKUN_COLOR_RESET" \
                "$description" \
                "$VOKUN_COLOR_DIM" "$match_reason" "$VOKUN_COLOR_RESET" \
                "$installed"
        fi
    done

    if [[ "$found" == false ]]; then
        printf '  No bundles matched "%s"\n' "$query"
    fi

    printf '\n'
}

# --- vokun install ---

vokun::bundles::install() {
    local name="${1:-}"

    if [[ -z "$name" ]]; then
        vokun::core::error "Usage: vokun install <bundle>"
        return 1
    fi

    local file
    file=$(vokun::bundles::find_by_name "$name") || {
        vokun::core::error "Bundle not found: $name"
        vokun::core::log "Run 'vokun list' to see available bundles."
        return 1
    }

    if vokun::state::is_installed "$name"; then
        vokun::core::warn "Bundle '$name' is already installed"
        vokun::core::log "Run 'vokun info $name' to see its contents."
        return 0
    fi

    vokun::toml::parse "$file"

    local description
    description=$(vokun::toml::get "meta.description" "")

    printf '\n%sInstalling bundle: %s%s\n' "$VOKUN_COLOR_BOLD" "$name" "$VOKUN_COLOR_RESET"
    [[ -n "$description" ]] && printf '%s\n' "$description"
    printf '%s\n' "$(printf '%.0s─' {1..50})"

    # Collect packages
    local -a repo_packages=()
    local -a aur_packages=()
    local -a optional_packages=()
    local -a already_installed=()
    local -a to_install=()

    # Regular packages
    local pkg_keys
    pkg_keys=$(vokun::toml::keys "packages")
    if [[ -n "$pkg_keys" ]]; then
        while IFS= read -r pkg; do
            [[ -z "$pkg" ]] && continue
            if vokun::core::is_pkg_installed "$pkg"; then
                already_installed+=("$pkg")
            else
                repo_packages+=("$pkg")
            fi
        done <<< "$pkg_keys"
    fi

    # AUR packages
    local aur_keys
    aur_keys=$(vokun::toml::keys "packages.aur")
    if [[ -n "$aur_keys" ]]; then
        while IFS= read -r pkg; do
            [[ -z "$pkg" ]] && continue
            if vokun::core::is_pkg_installed "$pkg"; then
                already_installed+=("$pkg")
            else
                aur_packages+=("$pkg")
            fi
        done <<< "$aur_keys"
    fi

    # Optional packages
    local opt_keys
    opt_keys=$(vokun::toml::keys "packages.optional")

    # Display what will be installed
    if [[ ${#repo_packages[@]} -gt 0 ]]; then
        printf '\n  %sPackages to install:%s\n' "$VOKUN_COLOR_GREEN" "$VOKUN_COLOR_RESET"
        for pkg in "${repo_packages[@]}"; do
            local desc
            desc=$(vokun::toml::get "packages.${pkg}")
            printf '    %s%-25s%s %s\n' "$VOKUN_COLOR_BOLD" "$pkg" "$VOKUN_COLOR_RESET" "${VOKUN_COLOR_DIM}${desc}${VOKUN_COLOR_RESET}"
        done
    fi

    if [[ ${#aur_packages[@]} -gt 0 ]]; then
        local aur_helper
        aur_helper=$(vokun::core::get_aur_helper)
        if [[ -z "$aur_helper" ]]; then
            printf '\n  %sAUR packages (skipped — no AUR helper found):%s\n' "$VOKUN_COLOR_YELLOW" "$VOKUN_COLOR_RESET"
            for pkg in "${aur_packages[@]}"; do
                printf '    %s (skipped)\n' "$pkg"
            done
            aur_packages=()
        else
            printf '\n  %sAUR packages (via %s):%s\n' "$VOKUN_COLOR_YELLOW" "$aur_helper" "$VOKUN_COLOR_RESET"
            for pkg in "${aur_packages[@]}"; do
                local desc
                desc=$(vokun::toml::get "packages.aur.${pkg}")
                printf '    %s%-25s%s %s\n' "$VOKUN_COLOR_BOLD" "$pkg" "$VOKUN_COLOR_RESET" "${VOKUN_COLOR_DIM}${desc}${VOKUN_COLOR_RESET}"
            done
        fi
    fi

    if [[ ${#already_installed[@]} -gt 0 ]]; then
        printf '\n  %sAlready installed:%s %s\n' "$VOKUN_COLOR_DIM" "$VOKUN_COLOR_RESET" "${already_installed[*]}"
    fi

    # Handle optional packages
    if [[ -n "$opt_keys" ]]; then
        printf '\n  %sOptional packages:%s\n' "$VOKUN_COLOR_CYAN" "$VOKUN_COLOR_RESET"
        local -a opt_list=()
        while IFS= read -r pkg; do
            [[ -z "$pkg" ]] && continue
            if ! vokun::core::is_pkg_installed "$pkg"; then
                opt_list+=("$pkg")
                local desc
                desc=$(vokun::toml::get "packages.optional.${pkg}")
                printf '    %-25s %s\n' "$pkg" "${VOKUN_COLOR_DIM}${desc}${VOKUN_COLOR_RESET}"
            fi
        done <<< "$opt_keys"

        if [[ ${#opt_list[@]} -gt 0 ]]; then
            printf '\n'
            printf '  Install optional packages too? [y/N] '
            local reply
            read -r reply
            if [[ "$reply" =~ ^[yY] ]]; then
                repo_packages+=("${opt_list[@]}")
                optional_packages=("${opt_list[@]}")
            fi
        fi
    fi

    # Summary
    to_install=("${repo_packages[@]}" "${aur_packages[@]}")
    local total=${#to_install[@]}

    if [[ $total -eq 0 ]]; then
        vokun::core::success "All packages are already installed!"
        # Still record the bundle in state
        local all_pkgs
        all_pkgs=$(printf '%s ' "${already_installed[@]}" "${optional_packages[@]}")
        vokun::state::add_bundle "$name" "$all_pkgs" "" "default"
        return 0
    fi

    printf '\n  %sTotal: %d new package(s) to install%s\n\n' "$VOKUN_COLOR_BOLD" "$total" "$VOKUN_COLOR_RESET"

    # Confirm
    if ! vokun::core::confirm "Proceed with installation?"; then
        vokun::core::log "Installation cancelled."
        return 1
    fi

    printf '\n'

    # Install repo packages
    local install_failed=false
    if [[ ${#repo_packages[@]} -gt 0 ]]; then
        vokun::core::run_pacman "-S" "--needed" "${repo_packages[@]}" || install_failed=true
    fi

    # Install AUR packages
    if [[ ${#aur_packages[@]} -gt 0 && "$install_failed" == false ]]; then
        local aur_helper
        aur_helper=$(vokun::core::get_aur_helper)
        vokun::core::show_cmd "$aur_helper -S --needed ${aur_packages[*]}"
        "$aur_helper" -S --needed "${aur_packages[@]}" || install_failed=true
    fi

    if [[ "$install_failed" == true ]]; then
        vokun::core::error "Some packages failed to install"
        return 1
    fi

    # Run post-install hooks
    local hooks
    hooks=$(vokun::toml::get "hooks.post_install" "")
    if [[ -n "$hooks" ]]; then
        printf '\n%sRunning post-install hooks...%s\n' "$VOKUN_COLOR_DIM" "$VOKUN_COLOR_RESET"
        while IFS= read -r hook_cmd; do
            [[ -z "$hook_cmd" ]] && continue
            vokun::core::show_cmd "$hook_cmd"
            # shellcheck disable=SC2294
            eval "$hook_cmd"
        done <<< "$hooks"
    fi

    # Update state
    local all_pkgs
    all_pkgs=$(printf '%s ' "${already_installed[@]}" "${repo_packages[@]}" "${aur_packages[@]}")
    local skipped_pkgs=""
    vokun::state::add_bundle "$name" "$all_pkgs" "$skipped_pkgs" "default"

    printf '\n'
    vokun::core::success "Bundle '$name' installed successfully!"
}

# --- vokun remove ---

vokun::bundles::remove() {
    local name="${1:-}"

    if [[ -z "$name" ]]; then
        vokun::core::error "Usage: vokun remove <bundle>"
        return 1
    fi

    if ! vokun::state::is_installed "$name"; then
        vokun::core::error "Bundle '$name' is not installed"
        return 1
    fi

    # Get packages in this bundle from state
    local -a bundle_pkgs
    mapfile -t bundle_pkgs < <(vokun::state::get_bundle_packages "$name")

    if [[ ${#bundle_pkgs[@]} -eq 0 ]]; then
        vokun::core::warn "No packages tracked for bundle '$name'"
        vokun::state::remove_bundle "$name"
        return 0
    fi

    # Find shared packages (in other bundles too)
    local -a shared_pkgs
    mapfile -t shared_pkgs < <(vokun::state::get_shared_packages "$name" "${bundle_pkgs[@]}")

    # Find unique packages (safe to remove)
    local -a unique_pkgs=()
    local -a kept_pkgs=()
    for pkg in "${bundle_pkgs[@]}"; do
        if vokun::core::in_array "$pkg" "${shared_pkgs[@]}"; then
            kept_pkgs+=("$pkg")
        elif vokun::core::is_pkg_installed "$pkg"; then
            unique_pkgs+=("$pkg")
        fi
    done

    printf '\n%sRemoving bundle: %s%s\n' "$VOKUN_COLOR_BOLD" "$name" "$VOKUN_COLOR_RESET"
    printf '%s\n' "$(printf '%.0s─' {1..50})"

    if [[ ${#unique_pkgs[@]} -gt 0 ]]; then
        printf '\n  %sPackages to remove:%s\n' "$VOKUN_COLOR_RED" "$VOKUN_COLOR_RESET"
        for pkg in "${unique_pkgs[@]}"; do
            printf '    %s\n' "$pkg"
        done
    fi

    if [[ ${#kept_pkgs[@]} -gt 0 ]]; then
        printf '\n  %sKept (shared with other bundles):%s %s\n' \
            "$VOKUN_COLOR_DIM" "$VOKUN_COLOR_RESET" "${kept_pkgs[*]}"
    fi

    if [[ ${#unique_pkgs[@]} -eq 0 ]]; then
        vokun::core::info "No packages to remove (all shared with other bundles)"
        vokun::state::remove_bundle "$name"
        vokun::core::success "Bundle '$name' removed from tracking."
        return 0
    fi

    printf '\n'
    if ! vokun::core::confirm "Remove ${#unique_pkgs[@]} package(s)?"; then
        vokun::core::log "Removal cancelled."
        return 1
    fi

    vokun::core::run_pacman_only "-Rns" "${unique_pkgs[@]}" || {
        vokun::core::error "Some packages failed to remove"
        return 1
    }

    vokun::state::remove_bundle "$name"
    printf '\n'
    vokun::core::success "Bundle '$name' removed!"
}
