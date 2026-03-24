#!/usr/bin/env bash
# shellcheck disable=SC2034
# vokun - Why command
# Show which bundles include a given package

vokun::why::run() {
    local pkg=""

    for arg in "$@"; do
        case "$arg" in
            --help|-h)
                vokun::core::help_command "why"
                return 0
                ;;
            *) [[ -z "$pkg" ]] && pkg="$arg" ;;
        esac
    done

    if [[ -z "$pkg" ]]; then
        vokun::core::error "Usage: vokun why <package>"
        return 1
    fi

    local -a bundle_files
    mapfile -t bundle_files < <(vokun::bundles::find_all)

    local -a matching_bundles=()
    local -a matching_installed=()

    for file in "${bundle_files[@]}"; do
        vokun::toml::parse "$file"

        local name
        name=$(vokun::bundles::name_from_path "$file")

        # Check all package sections
        local found=false
        local section
        for section in "packages" "packages.aur" "packages.optional"; do
            local keys
            keys=$(vokun::toml::keys "$section")
            [[ -z "$keys" ]] && continue
            while IFS= read -r key; do
                [[ "$key" == "$pkg" ]] && found=true && break
            done <<< "$keys"
            [[ "$found" == true ]] && break
        done

        if [[ "$found" == true ]]; then
            matching_bundles+=("$name")
            if vokun::state::is_installed "$name"; then
                matching_installed+=("yes")
            else
                matching_installed+=("no")
            fi
        fi
    done

    if [[ ${#matching_bundles[@]} -gt 0 ]]; then
        printf '\n%s%s%s is included in:\n' "$VOKUN_COLOR_BOLD" "$pkg" "$VOKUN_COLOR_RESET"
        local i
        for (( i=0; i<${#matching_bundles[@]}; i++ )); do
            local status
            if [[ "${matching_installed[$i]}" == "yes" ]]; then
                status="${VOKUN_COLOR_GREEN}installed${VOKUN_COLOR_RESET}"
            else
                status="${VOKUN_COLOR_DIM}not installed${VOKUN_COLOR_RESET}"
            fi
            printf '  %s (%s)\n' "${matching_bundles[$i]}" "$status"
        done
        printf '\n'
        return 0
    fi

    # Not in any bundle — check action log for ad-hoc install via `vokun get`
    if [[ -n "$VOKUN_LOG_FILE" && -f "$VOKUN_LOG_FILE" ]]; then
        local found_in_log=false
        while IFS='|' read -r timestamp action target details profile; do
            if [[ "$action" == "get" ]]; then
                local word
                # shellcheck disable=SC2086
                for word in $target; do
                    if [[ "$word" == "$pkg" ]]; then
                        found_in_log=true
                        break 2
                    fi
                done
            fi
        done < "$VOKUN_LOG_FILE"

        if [[ "$found_in_log" == true ]]; then
            printf '\n%s%s%s is not in any bundle.\n' "$VOKUN_COLOR_BOLD" "$pkg" "$VOKUN_COLOR_RESET"
            printf 'It was installed via %svokun get%s and never added to a bundle.\n\n' \
                "$VOKUN_COLOR_CYAN" "$VOKUN_COLOR_RESET"
            return 0
        fi
    fi

    printf '\n%s%s%s is not in any bundle.\n\n' "$VOKUN_COLOR_BOLD" "$pkg" "$VOKUN_COLOR_RESET"
}

# --- vokun untracked ---
# List packages installed via `vokun get` that aren't in any bundle

vokun::why::untracked() {
    for arg in "$@"; do
        case "$arg" in
            --help|-h)
                vokun::core::help_command "untracked"
                return 0
                ;;
        esac
    done

    if [[ -z "$VOKUN_LOG_FILE" || ! -f "$VOKUN_LOG_FILE" ]]; then
        vokun::core::info "No action log found. Nothing to report."
        return 0
    fi

    # Collect all packages ever installed via `vokun get`
    local -A got_packages=()
    while IFS='|' read -r timestamp action target details profile; do
        if [[ "$action" == "get" ]]; then
            local word
            # shellcheck disable=SC2086
            for word in $target; do
                [[ -n "$word" ]] && got_packages["$word"]=1
            done
        fi
    done < "$VOKUN_LOG_FILE"

    if [[ ${#got_packages[@]} -eq 0 ]]; then
        vokun::core::info "No packages found in the action log from 'vokun get'."
        return 0
    fi

    # Build set of all packages across all bundles
    local -A bundle_packages=()
    local -a bundle_files
    mapfile -t bundle_files < <(vokun::bundles::find_all)

    for file in "${bundle_files[@]}"; do
        vokun::toml::parse "$file"
        local section
        for section in "packages" "packages.aur" "packages.optional"; do
            local keys
            keys=$(vokun::toml::keys "$section")
            [[ -z "$keys" ]] && continue
            while IFS= read -r key; do
                [[ -n "$key" ]] && bundle_packages["$key"]=1
            done <<< "$keys"
        done
    done

    # Find untracked: in got_packages but not in any bundle
    local -a untracked=()
    local pkg
    for pkg in "${!got_packages[@]}"; do
        if [[ ! -v "bundle_packages[$pkg]" ]]; then
            untracked+=("$pkg")
        fi
    done

    if [[ ${#untracked[@]} -eq 0 ]]; then
        vokun::core::success "All packages from 'vokun get' are tracked in bundles."
        return 0
    fi

    # Sort for display
    mapfile -t untracked < <(printf '%s\n' "${untracked[@]}" | sort)

    printf '\n%sUntracked packages%s %s(installed via vokun get, not in any bundle)%s\n' \
        "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET" "$VOKUN_COLOR_DIM" "$VOKUN_COLOR_RESET"
    printf '%s\n\n' "$(printf '%.0s─' {1..50})"

    for pkg in "${untracked[@]}"; do
        local installed=""
        if vokun::core::is_pkg_installed "$pkg"; then
            installed="${VOKUN_COLOR_GREEN} [installed]${VOKUN_COLOR_RESET}"
        else
            installed="${VOKUN_COLOR_DIM} [removed]${VOKUN_COLOR_RESET}"
        fi
        printf '  %s%s\n' "$pkg" "$installed"
    done

    printf '\n%s%d untracked package(s).%s\n' "$VOKUN_COLOR_BOLD" "${#untracked[@]}" "$VOKUN_COLOR_RESET"
    printf '%sConsider adding them to a bundle with: vokun bundle add <bundle> <pkg>%s\n\n' \
        "$VOKUN_COLOR_DIM" "$VOKUN_COLOR_RESET"
}
