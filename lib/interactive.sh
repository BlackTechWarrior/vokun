#!/usr/bin/env bash
# shellcheck disable=SC2034
# vokun - Interactive first-run wizard
# Guides new users through initial bundle selection

# --- Category-to-tag mapping ---

# Maps wizard categories to bundle tags
declare -gA VOKUN_CATEGORY_TAGS=(
    [Development]="dev essentials"
    [System Admin]="admin cli"
    [Security]="sec hacking pentesting"
    [Gaming]="gaming fun"
    [Multimedia]="media creative"
    [Academic]="writing academic"
    [DevOps]="devops cloud"
)

# --- First-run check ---

# Check if this is a fresh install and launch the wizard if so.
# Check if this is a fresh install. Returns 0 if it handled things (first run),
# returns 1 if not first run (caller should launch browse).
vokun::interactive::first_run_check() {
    # Require jq for state inspection
    if ! command -v jq &>/dev/null; then
        return 1
    fi

    # Check if wizard was already dismissed or bundles are installed
    local bundle_count
    bundle_count=$(jq '.installed_bundles | length' "$VOKUN_STATE_FILE" 2>/dev/null || echo "0")
    local dismissed
    dismissed=$(jq -r '.wizard_dismissed // false' "$VOKUN_STATE_FILE" 2>/dev/null || echo "false")

    if [[ "$bundle_count" -gt 0 || "$dismissed" == "true" ]]; then
        # Not first run
        return 1
    fi

    # Fresh install — offer the wizard
    printf '\n'
    vokun::core::info "Looks like this is your first time running vokun."
    printf '  Would you like to run the setup wizard? [Y/n] '
    local reply
    read -r reply
    case "$reply" in
        [nN]|[nN][oO])
            # Remember the dismissal
            local tmp
            tmp=$(mktemp)
            jq '.wizard_dismissed = true' "$VOKUN_STATE_FILE" > "$tmp" && mv "$tmp" "$VOKUN_STATE_FILE"
            return 0
            ;;
    esac

    vokun::interactive::wizard
    return 0
}

# --- Wizard ---

vokun::interactive::wizard() {
    printf '\n'
    printf '%s%s' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_CYAN"
    printf '  Welcome to vokun - Package Bundle Manager for Arch Linux\n'
    printf '%s' "$VOKUN_COLOR_RESET"
    printf '%s\n' "$(printf '%.0s─' {1..60})"
    printf '\n'

    # --- Step 1: Detect AUR helper ---

    local aur_helper
    aur_helper=$(vokun::core::detect_aur_helper)

    if [[ -n "$aur_helper" ]]; then
        vokun::core::success "Detected AUR helper: $aur_helper"
        printf '  Use %s%s%s for AUR packages? [Y/n] ' "$VOKUN_COLOR_BOLD" "$aur_helper" "$VOKUN_COLOR_RESET"
        local reply
        read -r reply
        case "$reply" in
            [nN]|[nN][oO])
                aur_helper=""
                vokun::core::info "AUR packages will be skipped."
                ;;
        esac
    else
        vokun::core::warn "No AUR helper found (paru/yay)."
        vokun::core::log "  AUR packages will be skipped during installation."
        vokun::core::log "  Install paru or yay later if you need AUR support."
    fi

    printf '\n'

    # --- Step 2: Category selection ---

    local -a categories=("Development" "System Admin" "Security" "Gaming" "Multimedia" "Academic" "DevOps")
    local -a selected_categories=()

    vokun::core::info "What kind of work do you do?"
    printf '\n'

    if [[ "${VOKUN_FZF:-true}" == "true" ]] && command -v fzf &>/dev/null; then
        # Use fzf for multi-select
        local fzf_result
        fzf_result=$(printf '%s\n' "${categories[@]}" | fzf --multi \
            --header="Select categories (TAB to toggle, ENTER to confirm, ESC to cancel)" \
            --prompt="Categories> " \
            --no-info 2>/dev/null) || true

        if [[ -n "$fzf_result" ]]; then
            mapfile -t selected_categories <<< "$fzf_result"
        fi
    else
        # Numbered menu fallback
        local i=1
        for cat in "${categories[@]}"; do
            printf '    %s%d)%s %s\n' "$VOKUN_COLOR_BOLD" "$i" "$VOKUN_COLOR_RESET" "$cat"
            ((i++))
        done

        printf '\n  Enter numbers separated by spaces (e.g., 1 3 5): '
        local selection
        read -r selection

        # shellcheck disable=SC2086
        for num in $selection; do
            if [[ "$num" =~ ^[0-9]+$ ]] && (( num >= 1 && num <= ${#categories[@]} )); then
                selected_categories+=("${categories[$((num - 1))]}")
            fi
        done
    fi

    if [[ ${#selected_categories[@]} -eq 0 ]]; then
        vokun::core::info "No categories selected. You can install bundles later with 'vokun install'."
        printf '\n'
        return 0
    fi

    printf '\n  Selected: '
    printf '%s%s%s ' "$VOKUN_COLOR_CYAN" "${selected_categories[*]}" "$VOKUN_COLOR_RESET"
    printf '\n\n'

    # --- Step 3: Find matching bundles by tags ---

    local -a matching_tags=()
    for cat in "${selected_categories[@]}"; do
        local tags="${VOKUN_CATEGORY_TAGS[$cat]:-}"
        # shellcheck disable=SC2086
        for tag in $tags; do
            matching_tags+=("$tag")
        done
    done

    local -a bundle_files
    mapfile -t bundle_files < <(vokun::bundles::find_all)

    local -a matched_bundles=()  # "name|description|file" entries
    local -a seen_names=()

    for file in "${bundle_files[@]}"; do
        vokun::toml::parse "$file"

        local name description tags_str
        name=$(vokun::bundles::name_from_path "$file")
        description=$(vokun::toml::get "meta.description" "No description")
        tags_str=$(vokun::toml::get "meta.tags" "")

        # Check if any of the bundle's tags match our selected category tags
        local tag_match=false
        while IFS= read -r bundle_tag; do
            [[ -z "$bundle_tag" ]] && continue
            for mtag in "${matching_tags[@]}"; do
                if [[ "$bundle_tag" == "$mtag" ]]; then
                    tag_match=true
                    break 2
                fi
            done
        done <<< "$tags_str"

        if [[ "$tag_match" == true ]]; then
            # Avoid duplicates
            if ! vokun::core::in_array "$name" "${seen_names[@]+"${seen_names[@]}"}"; then
                matched_bundles+=("${name}|${description}|${file}")
                seen_names+=("$name")
            fi
        fi
    done

    if [[ ${#matched_bundles[@]} -eq 0 ]]; then
        vokun::core::info "No bundles matched your categories."
        vokun::core::log "  Run 'vokun list' to browse all available bundles."
        printf '\n'
        return 0
    fi

    # --- Step 4: Accept/Skip each bundle ---

    local -a selected_bundles=()
    local total_packages=0

    printf '%s\n' "$(printf '%.0s─' {1..60})"
    vokun::core::info "Found ${#matched_bundles[@]} matching bundle(s). Review each one:"
    printf '\n'

    for entry in "${matched_bundles[@]}"; do
        IFS='|' read -r name description file <<< "$entry"

        printf '  %s%s%s\n' "$VOKUN_COLOR_BOLD" "$name" "$VOKUN_COLOR_RESET"
        printf '  %s%s%s\n' "$VOKUN_COLOR_DIM" "$description" "$VOKUN_COLOR_RESET"

        # Count packages in this bundle
        vokun::toml::parse "$file"
        local pkg_count=0
        local pkg_keys
        pkg_keys=$(vokun::toml::keys "packages")
        if [[ -n "$pkg_keys" ]]; then
            pkg_count=$(echo "$pkg_keys" | grep -c .)
        fi
        local aur_keys
        aur_keys=$(vokun::toml::keys "packages.aur")
        if [[ -n "$aur_keys" ]]; then
            pkg_count=$((pkg_count + $(echo "$aur_keys" | grep -c .)))
        fi

        printf '  %s(%d packages)%s\n' "$VOKUN_COLOR_DIM" "$pkg_count" "$VOKUN_COLOR_RESET"

        printf '  [A]ccept / [S]kip? '
        local reply
        read -r reply
        case "$reply" in
            [sS]|[sS][kK][iI][pP])
                printf '  %s→ Skipped%s\n\n' "$VOKUN_COLOR_DIM" "$VOKUN_COLOR_RESET"
                ;;
            *)
                selected_bundles+=("$name")
                total_packages=$((total_packages + pkg_count))
                printf '  %s→ Accepted%s\n\n' "$VOKUN_COLOR_GREEN" "$VOKUN_COLOR_RESET"
                ;;
        esac
    done

    if [[ ${#selected_bundles[@]} -eq 0 ]]; then
        vokun::core::info "No bundles selected. You can install bundles later with 'vokun install'."
        printf '\n'
        return 0
    fi

    # --- Step 5: Summary and confirm ---

    printf '%s\n' "$(printf '%.0s─' {1..60})"
    printf '\n'
    vokun::core::info "Installation Summary"
    printf '  %sBundles:%s  %d\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET" "${#selected_bundles[@]}"
    printf '  %sPackages:%s ~%d\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET" "$total_packages"
    printf '\n'

    printf '  Bundles to install:\n'
    for name in "${selected_bundles[@]}"; do
        printf '    %s•%s %s\n' "$VOKUN_COLOR_GREEN" "$VOKUN_COLOR_RESET" "$name"
    done
    printf '\n'

    if ! vokun::core::confirm "Proceed with installation?"; then
        vokun::core::log "Setup cancelled. Run 'vokun install <bundle>' anytime."
        return 0
    fi

    # --- Step 6: Install each bundle ---

    printf '\n'

    for name in "${selected_bundles[@]}"; do
        vokun::bundles::install "$name"
        printf '\n'
    done

    printf '%s\n' "$(printf '%.0s─' {1..60})"
    vokun::core::success "Setup complete! You're all set."
    vokun::core::log ""
    vokun::core::log "Useful commands:"
    vokun::core::log "  vokun list          List all available bundles"
    vokun::core::log "  vokun info <bundle> Show bundle details"
    vokun::core::log "  vokun update        System update"
    vokun::core::log "  vokun help          Full command reference"
    printf '\n'
}

# --- Interactive bundle browser ---

vokun::interactive::browse() {
    if [[ "${VOKUN_FZF:-true}" == "true" ]] && command -v fzf &>/dev/null; then
        vokun::interactive::_browse_fzf
    else
        vokun::interactive::_browse_menu
    fi
}

# fzf-based bundle browser
vokun::interactive::_browse_fzf() {
    local -a bundle_files
    mapfile -t bundle_files < <(vokun::bundles::find_all)

    if [[ ${#bundle_files[@]} -eq 0 ]]; then
        vokun::core::warn "No bundles found"
        return 1
    fi

    # Build list of bundle names
    local -a bundle_names=()
    for file in "${bundle_files[@]}"; do
        bundle_names+=("$(vokun::bundles::name_from_path "$file")")
    done

    while true; do
        local selected
        selected=$(printf '%s\n' "${bundle_names[@]}" | fzf \
            --header="Select a bundle (ESC to quit)" \
            --prompt="Browse> " \
            --preview="vokun info {}" \
            --preview-window=right:60%:wrap \
            --no-info) || break

        [[ -z "$selected" ]] && break

        # Show info and action menu
        vokun::bundles::info "$selected"

        while true; do
            printf '  %s[I]%snstall / %s[R]%semove / %s[B]%sack? ' \
                "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET" \
                "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET" \
                "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET"
            local action
            read -r action
            case "$action" in
                [iI])
                    vokun::bundles::install "$selected"
                    break
                    ;;
                [rR])
                    vokun::bundles::remove "$selected"
                    break
                    ;;
                [bB]|"")
                    break
                    ;;
                *)
                    vokun::core::warn "Unknown action: $action"
                    ;;
            esac
        done
    done
}

# Numbered menu fallback browser
vokun::interactive::_browse_menu() {
    local -a bundle_files
    mapfile -t bundle_files < <(vokun::bundles::find_all)

    if [[ ${#bundle_files[@]} -eq 0 ]]; then
        vokun::core::warn "No bundles found"
        return 1
    fi

    # Build parallel arrays of names and descriptions
    local -a bundle_names=()
    local -a bundle_descs=()
    for file in "${bundle_files[@]}"; do
        local name desc
        name=$(vokun::bundles::name_from_path "$file")
        vokun::toml::parse "$file"
        desc=$(vokun::toml::get "meta.description" "No description")
        bundle_names+=("$name")
        bundle_descs+=("$desc")
    done

    local total=${#bundle_names[@]}

    while true; do
        printf '\n%s Available Bundles%s\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET"
        printf '%s\n\n' "$(printf '%.0s─' {1..50})"

        local i
        for ((i = 0; i < total; i++)); do
            local num=$((i + 1))
            local status=""
            if vokun::state::is_installed "${bundle_names[$i]}"; then
                status=" ${VOKUN_COLOR_GREEN}[installed]${VOKUN_COLOR_RESET}"
            fi
            printf '  %s%2d)%s %-20s %s%s%s%s\n' \
                "$VOKUN_COLOR_BOLD" "$num" "$VOKUN_COLOR_RESET" \
                "${bundle_names[$i]}" \
                "$VOKUN_COLOR_DIM" "${bundle_descs[$i]}" "$VOKUN_COLOR_RESET" \
                "$status"
        done

        printf '\n  %sEnter number for info, '\''i N'\'' to install, '\''r N'\'' to remove, '\''q'\'' to quit%s\n' \
            "$VOKUN_COLOR_DIM" "$VOKUN_COLOR_RESET"
        printf '  > '
        local input
        read -r input

        # Quit on empty input or 'q'
        case "$input" in
            q|Q|"") return 0 ;;
        esac

        # Parse input
        local cmd="" num=""
        if [[ "$input" =~ ^[iI][[:space:]]+([0-9]+)$ ]]; then
            cmd="install"
            num="${BASH_REMATCH[1]}"
        elif [[ "$input" =~ ^[rR][[:space:]]+([0-9]+)$ ]]; then
            cmd="remove"
            num="${BASH_REMATCH[1]}"
        elif [[ "$input" =~ ^[0-9]+$ ]]; then
            cmd="info"
            num="$input"
        else
            vokun::core::warn "Invalid input: $input"
            continue
        fi

        # Validate number
        if (( num < 1 || num > total )); then
            vokun::core::warn "Number out of range: $num (1-$total)"
            continue
        fi

        local selected="${bundle_names[$((num - 1))]}"

        case "$cmd" in
            info)
                vokun::bundles::info "$selected"
                ;;
            install)
                vokun::bundles::install "$selected"
                ;;
            remove)
                vokun::bundles::remove "$selected"
                ;;
        esac
    done
}
