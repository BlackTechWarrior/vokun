#!/usr/bin/env bash
# shellcheck disable=SC2034
# vokun - Setup command
# Check and install optional dependencies for full functionality

vokun::setup::run() {
    printf '\n%sVokun Dependency Check%s\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET"
    printf '%s\n\n' "$(printf '%.0s─' {1..50})"

    # Define dependencies: name|purpose|package|required
    local -a deps=(
        "pacman|Package manager|pacman|required"
        "bash|Shell (4.0+)|bash|required"
        "curl|HTTP requests (AUR checking, news)|curl|required"
        "jq|JSON state tracking|jq|recommended"
        "fzf|Interactive fuzzy picker|fzf|optional"
        "paru|AUR helper (preferred)|paru|optional"
        "yay|AUR helper (alternative)|yay|optional"
        "paccache|Cache management|pacman-contrib|optional"
    )

    local -a missing_recommended=()
    local -a missing_optional=()
    local has_aur_helper=false

    for entry in "${deps[@]}"; do
        IFS='|' read -r cmd purpose pkg level <<< "$entry"

        local status_icon status_color
        if command -v "$cmd" &>/dev/null; then
            status_icon="installed"
            status_color="$VOKUN_COLOR_GREEN"
            [[ "$cmd" == "paru" || "$cmd" == "yay" ]] && has_aur_helper=true
        else
            # For AUR helpers: if one is installed, the other is just "skipped" not "missing"
            if [[ ("$cmd" == "paru" || "$cmd" == "yay") && "$has_aur_helper" == true ]]; then
                status_icon="not needed"
                status_color="$VOKUN_COLOR_DIM"
            else
                status_icon="missing"
                status_color="$VOKUN_COLOR_RED"

                case "$level" in
                    recommended) missing_recommended+=("$pkg") ;;
                    optional)
                        if [[ "$cmd" == "paru" || "$cmd" == "yay" ]]; then
                            [[ "$cmd" == "paru" ]] && missing_optional+=("$cmd")
                        else
                            missing_optional+=("$pkg")
                        fi
                        ;;
                esac
            fi
        fi

        printf '  %s%-12s%s %-14s %s%-10s%s  %s\n' \
            "$VOKUN_COLOR_BOLD" "$cmd" "$VOKUN_COLOR_RESET" \
            "[$level]" \
            "$status_color" "$status_icon" "$VOKUN_COLOR_RESET" \
            "${VOKUN_COLOR_DIM}${purpose}${VOKUN_COLOR_RESET}"
    done

    printf '\n'

    # Check if paru needs to be bootstrapped (not a pacman package)
    local need_paru_bootstrap=false
    if [[ "$has_aur_helper" == false ]]; then
        need_paru_bootstrap=true
    fi

    # Collect what can be installed via pacman
    local -a pacman_install=()
    for pkg in "${missing_recommended[@]}"; do
        pacman_install+=("$pkg")
    done
    for pkg in "${missing_optional[@]}"; do
        # paru needs special handling — it's an AUR package
        if [[ "$pkg" == "paru" ]]; then
            continue
        fi
        pacman_install+=("$pkg")
    done

    if [[ ${#pacman_install[@]} -eq 0 && "$need_paru_bootstrap" == false ]]; then
        vokun::core::success "All dependencies are installed. Vokun is fully functional."
        return 0
    fi

    # Show what's missing and offer to install
    if [[ ${#pacman_install[@]} -gt 0 ]]; then
        printf '  %sMissing packages (installable via pacman):%s\n' "$VOKUN_COLOR_YELLOW" "$VOKUN_COLOR_RESET"
        for pkg in "${pacman_install[@]}"; do
            printf '    %s\n' "$pkg"
        done
        printf '\n'

        if vokun::core::confirm "Install these packages?"; then
            vokun::core::run_pacman_only "-S" "--needed" "${pacman_install[@]}"
            printf '\n'
        fi
    fi

    # Handle paru bootstrap
    if [[ "$need_paru_bootstrap" == true ]]; then
        printf '  %sNo AUR helper found.%s\n' "$VOKUN_COLOR_YELLOW" "$VOKUN_COLOR_RESET"
        printf '  paru is recommended for AUR support. It needs to be built from source.\n\n'

        if vokun::core::confirm "Bootstrap paru from AUR?"; then
            vokun::setup::bootstrap_paru
        else
            printf '\n'
            vokun::core::info "Skipped. You can install paru later manually:"
            vokun::core::log "  git clone https://aur.archlinux.org/paru.git"
            vokun::core::log "  cd paru && makepkg -si"
        fi
    fi

    printf '\n'
    vokun::core::success "Setup complete."
}

# Bootstrap paru from AUR source
vokun::setup::bootstrap_paru() {
    # Ensure base-devel is installed (needed for makepkg)
    vokun::core::show_cmd "sudo pacman -S --needed base-devel git"
    sudo pacman -S --needed base-devel git || {
        vokun::core::error "Failed to install build dependencies"
        return 1
    }

    local tmpdir
    tmpdir=$(mktemp -d)

    printf '\n'
    vokun::core::show_cmd "git clone https://aur.archlinux.org/paru.git $tmpdir/paru"
    git clone https://aur.archlinux.org/paru.git "$tmpdir/paru" || {
        vokun::core::error "Failed to clone paru"
        rm -rf "$tmpdir"
        return 1
    }

    vokun::core::show_cmd "cd $tmpdir/paru && makepkg -si"
    (cd "$tmpdir/paru" && makepkg -si) || {
        vokun::core::error "Failed to build paru"
        rm -rf "$tmpdir"
        return 1
    }

    rm -rf "$tmpdir"

    if command -v paru &>/dev/null; then
        vokun::core::success "paru installed successfully."
    else
        vokun::core::error "paru installation may have failed. Check the output above."
        return 1
    fi
}
