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

# --- vokun uninstall ---

vokun::setup::uninstall() {
    printf '\n%sVokun Uninstall%s\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET"
    printf '%s\n\n' "$(printf '%.0s─' {1..50})"

    # Check if vokun was installed via pacman (AUR package)
    if pacman -Qi vokun &>/dev/null; then
        vokun::core::info "Vokun was installed as a pacman/AUR package."
        printf '\n  Uninstall it with your package manager instead:\n\n'
        printf '    %ssudo pacman -Rns vokun%s\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET"
        local aur_helper
        aur_helper=$(vokun::core::get_aur_helper)
        if [[ -n "$aur_helper" ]]; then
            printf '    %s# or: %s -Rns vokun%s\n' "$VOKUN_COLOR_DIM" "$aur_helper" "$VOKUN_COLOR_RESET"
        fi
        printf '\n  Removing files manually would corrupt pacman'\''s database.\n\n'
        return 0
    fi

    # Detect where vokun is installed
    local vokun_bin
    vokun_bin=$(command -v vokun 2>/dev/null || true)

    if [[ -z "$vokun_bin" ]]; then
        vokun::core::warn "vokun binary not found in PATH"
    fi

    # Determine prefix from binary location
    local prefix=""
    if [[ "$vokun_bin" == "/usr/local/bin/vokun" ]]; then
        prefix="/usr/local"
    elif [[ "$vokun_bin" == "/usr/bin/vokun" ]]; then
        prefix="/usr"
    fi

    # List everything that will be removed
    printf '  %sThe following will be removed:%s\n\n' "$VOKUN_COLOR_RED" "$VOKUN_COLOR_RESET"

    local -a files_to_remove=()
    local -a dirs_to_remove=()

    # Binary
    if [[ -n "$vokun_bin" ]]; then
        printf '    %s\n' "$vokun_bin"
        files_to_remove+=("$vokun_bin")
    fi

    # Lib and bundles
    if [[ -n "$prefix" ]]; then
        local share_dir="${prefix}/share/vokun"
        if [[ -d "$share_dir" ]]; then
            printf '    %s/  (lib, bundles)\n' "$share_dir"
            dirs_to_remove+=("$share_dir")
        fi

        # Completions
        local bash_comp="${prefix}/share/bash-completion/completions/vokun"
        local zsh_comp="${prefix}/share/zsh/site-functions/_vokun"
        local fish_comp="${prefix}/share/fish/vendor_completions.d/vokun.fish"
        local license_dir="${prefix}/share/licenses/vokun"

        for f in "$bash_comp" "$zsh_comp" "$fish_comp"; do
            if [[ -f "$f" ]]; then
                printf '    %s\n' "$f"
                files_to_remove+=("$f")
            fi
        done
        if [[ -d "$license_dir" ]]; then
            printf '    %s/\n' "$license_dir"
            dirs_to_remove+=("$license_dir")
        fi
    fi

    # Pacman hook
    local hook="/usr/share/libalpm/hooks/vokun-notify.hook"
    if [[ -f "$hook" ]]; then
        printf '    %s\n' "$hook"
        files_to_remove+=("$hook")
    fi

    # User config
    local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/vokun"
    if [[ -d "$config_dir" ]]; then
        printf '\n    %s/  (config, state, custom bundles)\n' "$config_dir"
    fi

    printf '\n'

    if [[ ${#files_to_remove[@]} -eq 0 && ${#dirs_to_remove[@]} -eq 0 ]]; then
        vokun::core::warn "No system files found to remove."
        return 0
    fi

    if ! vokun::core::confirm "Remove all vokun system files? (requires sudo)"; then
        vokun::core::log "Uninstall cancelled."
        return 1
    fi

    # Remove system files
    for f in "${files_to_remove[@]}"; do
        vokun::core::show_cmd "sudo rm -f $f"
        sudo rm -f "$f"
    done
    for d in "${dirs_to_remove[@]}"; do
        vokun::core::show_cmd "sudo rm -rf $d"
        sudo rm -rf "$d"
    done

    vokun::core::success "System files removed."

    # Ask about user config
    if [[ -d "$config_dir" ]]; then
        printf '\n'
        printf '  Your config directory still exists at:\n'
        printf '    %s\n\n' "$config_dir"
        printf '  This contains your custom bundles, state, and settings.\n\n'
        if vokun::core::confirm "Delete config directory too?"; then
            rm -rf "$config_dir"
            vokun::core::success "Config directory removed."
        else
            vokun::core::info "Config kept at $config_dir"
        fi
    fi

    printf '\n'
    vokun::core::success "Vokun has been uninstalled."
}
