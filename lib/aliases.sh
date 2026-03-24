#!/usr/bin/env bash
# vokun - Package management aliases
# Thin wrappers around pacman/paru with transparency

# --- vokun get ---
vokun::aliases::get() {
    if [[ $# -eq 0 ]]; then
        vokun::core::error "Usage: vokun get <package> [package...]"
        return 1
    fi

    vokun::core::run_pacman "-S" "--needed" "$@"
    local exit_code=$?

    if [[ $exit_code -eq 0 && "${VOKUN_SYNC_AUTO_PROMPT:-true}" == "true" ]]; then
        printf '\n'
        printf '%sAdd to a bundle? [bundle name/new/n]: %s' "$VOKUN_COLOR_CYAN" "$VOKUN_COLOR_RESET"
        local reply
        read -r reply
        if [[ -n "$reply" && "$reply" != "n" && "$reply" != "N" ]]; then
            if [[ "$reply" == "new" ]]; then
                # Create a new bundle and add the package(s)
                printf 'Bundle name: '
                local new_name
                read -r new_name
                if [[ -n "$new_name" ]]; then
                    vokun::bundle_mgmt::create "$new_name"
                    # Add the packages to the new bundle
                    vokun::bundle_mgmt::add "$new_name" "$@"
                fi
            elif vokun::state::is_installed "$reply"; then
                # Bundle exists in state — add package to its state tracking
                local current_pkgs
                current_pkgs=$(vokun::state::get_bundle_packages "$reply" | tr '\n' ' ')
                # shellcheck disable=SC2086
                vokun::state::add_bundle "$reply" "${current_pkgs}$* " "" "default"
                vokun::core::success "Added to bundle '$reply'"
            elif vokun::bundles::find_by_name "$reply" &>/dev/null; then
                # Bundle exists as a TOML file but isn't installed yet — add to the file
                vokun::bundle_mgmt::add "$reply" "$@"
                vokun::core::success "Added to bundle '$reply'"
            else
                vokun::core::warn "Bundle '$reply' not found."
                printf '  Create it? [Y/n] '
                local create_reply
                read -r create_reply
                case "$create_reply" in
                    [nN]|[nN][oO]) ;;
                    *)
                        vokun::bundle_mgmt::create "$reply"
                        vokun::bundle_mgmt::add "$reply" "$@"
                        ;;
                esac
            fi
        fi
    fi

    return $exit_code
}

# --- vokun yeet ---
vokun::aliases::yeet() {
    if [[ $# -eq 0 ]]; then
        vokun::core::error "Usage: vokun yeet <package> [package...]"
        return 1
    fi

    # Check if any packages are in bundles
    local -a installed_bundles
    mapfile -t installed_bundles < <(vokun::state::get_installed_bundles)

    for pkg in "$@"; do
        for bundle in "${installed_bundles[@]}"; do
            local bundle_pkgs
            bundle_pkgs=$(vokun::state::get_bundle_packages "$bundle")
            if echo "$bundle_pkgs" | grep -qx "$pkg"; then
                vokun::core::warn "'$pkg' belongs to bundle '$bundle'"
            fi
        done
    done

    vokun::core::run_pacman_only "-Rns" "$@"
}

# --- vokun find ---
vokun::aliases::find() {
    local use_aur=false
    local -a query_args=()

    for arg in "$@"; do
        case "$arg" in
            --aur) use_aur=true ;;
            *) query_args+=("$arg") ;;
        esac
    done

    if [[ ${#query_args[@]} -eq 0 ]]; then
        vokun::core::error "Usage: vokun find <query> [--aur]"
        return 1
    fi

    if [[ "$use_aur" == true ]]; then
        local aur_helper
        aur_helper=$(vokun::core::get_aur_helper)
        if [[ -n "$aur_helper" ]]; then
            vokun::core::show_cmd "$aur_helper -Ss ${query_args[*]}"
            "$aur_helper" -Ss "${query_args[@]}"
        else
            vokun::core::warn "No AUR helper found. Searching repos only."
            vokun::core::run_pacman_only "-Ss" "${query_args[@]}"
        fi
    else
        vokun::core::run_pacman_only "-Ss" "${query_args[@]}"
    fi
}

# --- vokun which ---
vokun::aliases::which() {
    if [[ $# -eq 0 ]]; then
        vokun::core::error "Usage: vokun which <package>"
        return 1
    fi

    vokun::core::run_pacman_only "-Qi" "$@"
}

# --- vokun owns ---
vokun::aliases::owns() {
    if [[ $# -eq 0 ]]; then
        vokun::core::error "Usage: vokun owns <file>"
        return 1
    fi

    vokun::core::run_pacman_only "-Qo" "$@"
}

# --- vokun update ---
vokun::aliases::update() {
    local use_aur=false

    for arg in "$@"; do
        case "$arg" in
            --aur) use_aur=true ;;
        esac
    done

    if [[ "$use_aur" == true ]]; then
        local aur_helper
        aur_helper=$(vokun::core::get_aur_helper)
        if [[ -n "$aur_helper" ]]; then
            vokun::core::show_cmd "$aur_helper -Syu"
            "$aur_helper" -Syu
        else
            vokun::core::warn "No AUR helper found. Updating repos only."
            vokun::core::run_pacman_only "-Syu"
        fi
    else
        vokun::core::run_pacman_only "-Syu"
    fi
}

# --- vokun orphans ---
vokun::aliases::orphans() {
    local clean=false

    for arg in "$@"; do
        case "$arg" in
            --clean) clean=true ;;
        esac
    done

    if [[ "$clean" == true ]]; then
        local orphans
        orphans=$(pacman -Qdtq 2>/dev/null || true)
        if [[ -z "$orphans" ]]; then
            vokun::core::success "No orphaned packages found."
            return 0
        fi

        vokun::core::info "Removing orphaned packages:"
        printf '%s\n' "$orphans"
        printf '\n'

        if vokun::core::confirm "Remove these packages?"; then
            # shellcheck disable=SC2086
            vokun::core::show_cmd "sudo pacman -Rns $orphans"
            # shellcheck disable=SC2086
            sudo pacman -Rns $orphans
        fi
    else
        vokun::core::show_cmd "pacman -Qdt"
        local result
        result=$(pacman -Qdt 2>/dev/null || true)
        if [[ -z "$result" ]]; then
            vokun::core::success "No orphaned packages found."
        else
            printf '%s\n' "$result"
            printf '\n%sRun %svokun orphans --clean%s to remove them.%s\n' \
                "$VOKUN_COLOR_DIM" "$VOKUN_COLOR_RESET${VOKUN_COLOR_BOLD}" \
                "$VOKUN_COLOR_RESET${VOKUN_COLOR_DIM}" "$VOKUN_COLOR_RESET"
        fi
    fi
}

# --- vokun cache ---
vokun::aliases::cache() {
    local action=""

    for arg in "$@"; do
        case "$arg" in
            --clean) action="clean" ;;
            --purge) action="purge" ;;
        esac
    done

    case "$action" in
        clean)
            if ! command -v paccache &>/dev/null; then
                vokun::core::error "paccache not found. Install pacman-contrib:"
                vokun::core::log "  vokun get pacman-contrib"
                return 1
            fi
            vokun::core::show_cmd "sudo paccache -rk2"
            sudo paccache -rk2
            ;;
        purge)
            if ! command -v paccache &>/dev/null; then
                vokun::core::error "paccache not found. Install pacman-contrib:"
                vokun::core::log "  vokun get pacman-contrib"
                return 1
            fi
            vokun::core::warn "This will remove ALL cached packages!"
            if vokun::core::confirm "Continue?"; then
                vokun::core::show_cmd "sudo paccache -rk0"
                sudo paccache -rk0
            fi
            ;;
        *)
            # Show cache info
            local cache_dir="/var/cache/pacman/pkg"
            if [[ -d "$cache_dir" ]]; then
                local count size
                count=$(find "$cache_dir" -maxdepth 1 -name '*.pkg.tar.*' 2>/dev/null | wc -l || true)
                size=$(du -sh "$cache_dir" 2>/dev/null | cut -f1 || true)
                printf '%sPackage cache:%s\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET"
                printf '  Location:  %s\n' "$cache_dir"
                printf '  Packages:  %s\n' "$count"
                printf '  Size:      %s\n' "${size:-unknown}"
                printf '\n%sUse --clean (keep 2 versions) or --purge (remove all)%s\n' \
                    "$VOKUN_COLOR_DIM" "$VOKUN_COLOR_RESET"
            fi
            ;;
    esac
}

# --- vokun size ---
vokun::aliases::size() {
    local top=20

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --top)
                top="${2:-20}"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    vokun::core::show_cmd "pacman -Qi | sorting by installed size"
    printf '%s%-35s %s%s\n' "$VOKUN_COLOR_BOLD" "Package" "Size" "$VOKUN_COLOR_RESET"
    printf '%s\n' "$(printf '%.0s─' {1..50})"

    {
        pacman -Qi 2>/dev/null | \
            awk '/^Name/ {name=$3}
                 /^Installed Size/ {
                     size=$4; unit=$5;
                     # Normalize to bytes for sorting
                     bytes=size;
                     if (unit == "KiB") bytes=size*1024;
                     else if (unit == "MiB") bytes=size*1024*1024;
                     else if (unit == "GiB") bytes=size*1024*1024*1024;
                     printf "%015.0f %s %s %s\n", bytes, size, unit, name
                 }' | \
            sort -rn | \
            head -n "$top" | \
            while read -r _ size unit name; do
                printf '  %-35s %s %s\n' "$name" "$size" "$unit"
            done
    } 2>/dev/null || true
}

# --- vokun recent ---
vokun::aliases::recent() {
    local count=20

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --count)
                count="${2:-20}"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    vokun::core::show_cmd "grep 'installed' /var/log/pacman.log | tail -$count"
    printf '%sRecently installed packages:%s\n\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET"

    grep '\[ALPM\] installed' /var/log/pacman.log 2>/dev/null | \
        tail -n "$count" | \
        while IFS= read -r line; do
            # Extract date and package info
            local date pkg
            date=$(echo "$line" | grep -oP '^\[\K[^\]]+')
            pkg=$(echo "$line" | grep -oP 'installed \K\S+')
            printf '  %s%-25s%s %s%s%s\n' "$VOKUN_COLOR_BOLD" "$pkg" "$VOKUN_COLOR_RESET" \
                "$VOKUN_COLOR_DIM" "$date" "$VOKUN_COLOR_RESET"
        done
}

# --- vokun foreign ---
vokun::aliases::foreign() {
    vokun::core::show_cmd "pacman -Qm"
    printf '%sForeign/AUR packages:%s\n\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET"
    pacman -Qm 2>/dev/null
}

# --- vokun explicit ---
vokun::aliases::explicit() {
    vokun::core::show_cmd "pacman -Qe"
    pacman -Qe 2>/dev/null
}

# --- vokun broken ---
vokun::aliases::broken() {
    local found_issues=false

    printf '%sBroken Package Check%s\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET"
    printf '%s\n\n' "$(printf '%.0s─' {1..50})"

    # 1. Broken symlinks
    printf '  %sChecking for broken symlinks...%s\n' "$VOKUN_COLOR_DIM" "$VOKUN_COLOR_RESET"
    vokun::core::show_cmd "find /usr/bin /usr/lib /usr/share -xtype l"
    local broken_links
    broken_links=$(find /usr/bin /usr/lib /usr/share -xtype l 2>/dev/null | head -20 || true)
    if [[ -n "$broken_links" ]]; then
        found_issues=true
        local link_count
        link_count=$(echo "$broken_links" | wc -l)
        printf '  %s%d broken symlink(s) found:%s\n' "$VOKUN_COLOR_YELLOW" "$link_count" "$VOKUN_COLOR_RESET"
        while IFS= read -r link; do
            printf '    %s\n' "$link"
        done <<< "$broken_links"
    else
        printf '  %sNo broken symlinks found.%s\n' "$VOKUN_COLOR_GREEN" "$VOKUN_COLOR_RESET"
    fi

    printf '\n'

    # 2. Missing dependencies
    printf '  %sChecking dependency integrity...%s\n' "$VOKUN_COLOR_DIM" "$VOKUN_COLOR_RESET"
    vokun::core::show_cmd "pacman -Dk"
    local dep_issues
    dep_issues=$(pacman -Dk 2>&1 | grep -i "error\|warning" || true)
    if [[ -n "$dep_issues" ]]; then
        found_issues=true
        printf '  %sDependency issues found:%s\n' "$VOKUN_COLOR_YELLOW" "$VOKUN_COLOR_RESET"
        while IFS= read -r line; do
            printf '    %s\n' "$line"
        done <<< "$dep_issues"
    else
        printf '  %sDependency integrity OK.%s\n' "$VOKUN_COLOR_GREEN" "$VOKUN_COLOR_RESET"
    fi

    printf '\n'

    # 3. Missing files
    printf '  %sChecking for packages with missing files...%s\n' "$VOKUN_COLOR_DIM" "$VOKUN_COLOR_RESET"
    vokun::core::show_cmd "pacman -Qk"
    local missing_files
    missing_files=$(pacman -Qk 2>&1 | grep -v '0 missing files' | head -20 || true)
    if [[ -n "$missing_files" ]]; then
        found_issues=true
        local missing_count
        missing_count=$(echo "$missing_files" | wc -l)
        printf '  %s%d package(s) with missing files:%s\n' "$VOKUN_COLOR_YELLOW" "$missing_count" "$VOKUN_COLOR_RESET"
        while IFS= read -r line; do
            printf '    %s\n' "$line"
        done <<< "$missing_files"
    else
        printf '  %sAll package files intact.%s\n' "$VOKUN_COLOR_GREEN" "$VOKUN_COLOR_RESET"
    fi

    printf '\n'

    if [[ "$found_issues" == false ]]; then
        vokun::core::success "System is clean — no broken packages found."
    else
        vokun::core::warn "Issues found. Review the output above."
    fi
}
