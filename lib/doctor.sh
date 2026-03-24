#!/usr/bin/env bash
# shellcheck disable=SC2034
# vokun - Doctor command
# Run all health checks and give a pass/warn/fail summary

vokun::doctor::run() {
    for arg in "$@"; do
        case "$arg" in
            --help|-h)
                vokun::core::help_command "doctor"
                return 0
                ;;
        esac
    done

    printf '\n%sVokun Health Check%s\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET"
    printf '%s\n\n' "$(printf '%.0s─' {1..50})"

    local -a results=()
    local -a suggestions=()

    # --- 1. Dependency check ---
    printf '  %sChecking dependencies...%s\n' "$VOKUN_COLOR_DIM" "$VOKUN_COLOR_RESET"

    local -a required_cmds=("pacman" "bash" "curl")
    local -a recommended_cmds=("jq")
    local -a optional_cmds=("fzf" "paccache")
    local deps_ok=true

    for cmd in "${required_cmds[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            results+=("${VOKUN_COLOR_RED}FAIL${VOKUN_COLOR_RESET}  Dependencies    Missing required: $cmd")
            suggestions+=("Run: sudo pacman -S $cmd")
            deps_ok=false
        fi
    done

    for cmd in "${recommended_cmds[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            results+=("${VOKUN_COLOR_YELLOW}WARN${VOKUN_COLOR_RESET}  Dependencies    Missing recommended: $cmd")
            suggestions+=("Run: sudo pacman -S $cmd")
            deps_ok=false
        fi
    done

    local has_aur_helper=false
    command -v paru &>/dev/null && has_aur_helper=true
    command -v yay &>/dev/null && has_aur_helper=true
    if [[ "$has_aur_helper" == false ]]; then
        results+=("${VOKUN_COLOR_YELLOW}WARN${VOKUN_COLOR_RESET}  Dependencies    No AUR helper found (paru/yay)")
        suggestions+=("Run: vokun setup")
    fi

    if [[ "$deps_ok" == true && "$has_aur_helper" == true ]]; then
        local missing_optional=false
        for cmd in "${optional_cmds[@]}"; do
            command -v "$cmd" &>/dev/null || missing_optional=true
        done
        if [[ "$missing_optional" == true ]]; then
            results+=("${VOKUN_COLOR_YELLOW}WARN${VOKUN_COLOR_RESET}  Dependencies    Some optional tools missing")
            suggestions+=("Run: vokun setup")
        else
            results+=("${VOKUN_COLOR_GREEN}PASS${VOKUN_COLOR_RESET}  Dependencies    All dependencies installed")
        fi
    fi

    # --- 2. Sync drift detection ---
    printf '  %sChecking sync drift...%s\n' "$VOKUN_COLOR_DIM" "$VOKUN_COLOR_RESET"

    if command -v jq &>/dev/null; then
        # Forward drift: explicitly installed but not tracked
        local tracked_pkgs
        tracked_pkgs=$(vokun::state::get_all_tracked_packages)
        local unmanaged_pkgs
        unmanaged_pkgs=$(vokun::sync::get_unmanaged)

        local explicit_pkgs
        explicit_pkgs=$(pacman -Qeq 2>/dev/null)

        local drift_count=0
        while IFS= read -r pkg; do
            [[ -z "$pkg" ]] && continue
            if ! echo "$tracked_pkgs" | grep -qx "$pkg" && \
               ! echo "$unmanaged_pkgs" | grep -qx "$pkg"; then
                drift_count=$((drift_count + 1))
            fi
        done <<< "$explicit_pkgs"

        if [[ $drift_count -gt 0 ]]; then
            results+=("${VOKUN_COLOR_YELLOW}WARN${VOKUN_COLOR_RESET}  Sync drift      $drift_count untracked explicit package(s)")
            suggestions+=("Run: vokun sync")
        fi

        # Reverse drift: tracked but not installed
        local reverse_count=0
        local -a installed_bundles
        mapfile -t installed_bundles < <(vokun::state::get_installed_bundles)
        for bundle in "${installed_bundles[@]}"; do
            [[ -z "$bundle" ]] && continue
            local bundle_pkgs
            bundle_pkgs=$(vokun::state::get_bundle_packages "$bundle")
            while IFS= read -r pkg; do
                [[ -z "$pkg" ]] && continue
                if ! vokun::core::is_pkg_installed "$pkg"; then
                    reverse_count=$((reverse_count + 1))
                fi
            done <<< "$bundle_pkgs"
        done

        if [[ $reverse_count -gt 0 ]]; then
            results+=("${VOKUN_COLOR_YELLOW}WARN${VOKUN_COLOR_RESET}  Sync drift      $reverse_count tracked package(s) not installed")
            suggestions+=("Run: vokun sync")
        fi

        if [[ $drift_count -eq 0 && $reverse_count -eq 0 ]]; then
            results+=("${VOKUN_COLOR_GREEN}PASS${VOKUN_COLOR_RESET}  Sync drift      System in sync with bundle state")
        fi
    else
        results+=("${VOKUN_COLOR_YELLOW}WARN${VOKUN_COLOR_RESET}  Sync drift      Skipped (jq not installed)")
    fi

    # --- 3. Broken symlinks and missing deps ---
    printf '  %sChecking system integrity...%s\n' "$VOKUN_COLOR_DIM" "$VOKUN_COLOR_RESET"

    local broken_links
    broken_links=$(find /usr/bin /usr/lib /usr/share -xtype l 2>/dev/null | wc -l || echo 0)

    local dep_issues
    dep_issues=$(pacman -Dk 2>&1 | grep -ci "error\|warning" || true)

    if [[ $broken_links -gt 0 || $dep_issues -gt 0 ]]; then
        local detail=""
        [[ $broken_links -gt 0 ]] && detail+="$broken_links broken symlink(s)"
        [[ $dep_issues -gt 0 ]] && detail+="${detail:+, }$dep_issues dependency issue(s)"
        results+=("${VOKUN_COLOR_YELLOW}WARN${VOKUN_COLOR_RESET}  Integrity       $detail")
        suggestions+=("Run: vokun broken")
    else
        results+=("${VOKUN_COLOR_GREEN}PASS${VOKUN_COLOR_RESET}  Integrity       No broken symlinks or missing deps")
    fi

    # --- 4. Orphaned packages ---
    printf '  %sChecking for orphans...%s\n' "$VOKUN_COLOR_DIM" "$VOKUN_COLOR_RESET"

    local orphan_count
    orphan_count=$(pacman -Qdtq 2>/dev/null | wc -l || echo 0)

    if [[ $orphan_count -gt 0 ]]; then
        results+=("${VOKUN_COLOR_YELLOW}WARN${VOKUN_COLOR_RESET}  Orphans         $orphan_count orphaned package(s)")
        suggestions+=("Run: vokun orphans --clean")
    else
        results+=("${VOKUN_COLOR_GREEN}PASS${VOKUN_COLOR_RESET}  Orphans         No orphaned packages")
    fi

    # --- 5. Cache size ---
    printf '  %sChecking cache size...%s\n' "$VOKUN_COLOR_DIM" "$VOKUN_COLOR_RESET"

    local cache_dir="/var/cache/pacman/pkg"
    if [[ -d "$cache_dir" ]]; then
        local cache_size_bytes
        cache_size_bytes=$(du -sb "$cache_dir" 2>/dev/null | awk '{print $1}' || echo 0)
        # Default threshold: 5 GB
        local cache_threshold=$((5 * 1024 * 1024 * 1024))

        local cache_human
        cache_human=$(du -sh "$cache_dir" 2>/dev/null | awk '{print $1}' || echo "unknown")

        if [[ $cache_size_bytes -gt $cache_threshold ]]; then
            results+=("${VOKUN_COLOR_YELLOW}WARN${VOKUN_COLOR_RESET}  Cache           Package cache is $cache_human")
            suggestions+=("Run: vokun cache --clean")
        else
            results+=("${VOKUN_COLOR_GREEN}PASS${VOKUN_COLOR_RESET}  Cache           Package cache is $cache_human")
        fi
    fi

    # --- 6. Untracked packages ---
    printf '  %sChecking for untracked packages...%s\n' "$VOKUN_COLOR_DIM" "$VOKUN_COLOR_RESET"

    if [[ -n "$VOKUN_LOG_FILE" && -f "$VOKUN_LOG_FILE" ]]; then
        # Collect packages from vokun get
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

        if [[ ${#got_packages[@]} -gt 0 ]]; then
            # Build bundle package set
            local -A all_bundle_pkgs=()
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
                        [[ -n "$key" ]] && all_bundle_pkgs["$key"]=1
                    done <<< "$keys"
                done
            done

            local untracked_count=0
            for pkg in "${!got_packages[@]}"; do
                [[ ! -v "all_bundle_pkgs[$pkg]" ]] && untracked_count=$((untracked_count + 1))
            done

            if [[ $untracked_count -gt 0 ]]; then
                results+=("${VOKUN_COLOR_YELLOW}WARN${VOKUN_COLOR_RESET}  Untracked       $untracked_count package(s) from 'vokun get' not in any bundle")
                suggestions+=("Run: vokun untracked")
            else
                results+=("${VOKUN_COLOR_GREEN}PASS${VOKUN_COLOR_RESET}  Untracked       All ad-hoc installs tracked in bundles")
            fi
        else
            results+=("${VOKUN_COLOR_GREEN}PASS${VOKUN_COLOR_RESET}  Untracked       No ad-hoc package installs found")
        fi
    else
        results+=("${VOKUN_COLOR_GREEN}PASS${VOKUN_COLOR_RESET}  Untracked       No action log yet")
    fi

    # --- Summary ---
    printf '\n%sSummary%s\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET"
    printf '%s\n\n' "$(printf '%.0s─' {1..50})"

    for result in "${results[@]}"; do
        printf '  %s\n' "$result"
    done

    if [[ ${#suggestions[@]} -gt 0 ]]; then
        printf '\n%sRecommended actions:%s\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET"
        # Deduplicate suggestions
        local -A seen_suggestions=()
        for suggestion in "${suggestions[@]}"; do
            if [[ ! -v "seen_suggestions[$suggestion]" ]]; then
                seen_suggestions["$suggestion"]=1
                printf '  %s%s%s\n' "$VOKUN_COLOR_DIM" "$suggestion" "$VOKUN_COLOR_RESET"
            fi
        done
    else
        printf '\n%sAll checks passed!%s\n' "$VOKUN_COLOR_GREEN" "$VOKUN_COLOR_RESET"
    fi

    printf '\n'
}
