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

    # Check custom bundles FIRST — user overrides take priority
    if [[ -f "${VOKUN_CONFIG_DIR}/bundles/custom/${name}.toml" ]]; then
        printf '%s' "${VOKUN_CONFIG_DIR}/bundles/custom/${name}.toml"
        return
    fi

    # Fall back to system bundles
    if [[ -n "$VOKUN_SYSTEM_BUNDLE_DIR" && -f "${VOKUN_SYSTEM_BUNDLE_DIR}/${name}.toml" ]]; then
        printf '%s' "${VOKUN_SYSTEM_BUNDLE_DIR}/${name}.toml"
        return
    fi

    return 1
}

# Load a bundle's packages, resolving the extends chain
# Supports both single string and array extends:
#   extends = "parent"
#   extends = ["parent1", "parent2"]
# Parents cannot themselves have extends (single-level restriction).
# After calling this, TOML_DATA/TOML_SECTION_KEYS contain the merged result
# Usage: vokun::bundles::load_with_extends "/path/to/bundle.toml"
vokun::bundles::load_with_extends() {
    local file="$1"
    local -a _extends_chain=()
    if [[ $# -ge 2 ]]; then
        # Receive the cycle-detection chain from the caller
        shift
        _extends_chain=("$@")
    fi

    vokun::toml::parse "$file"

    local extends_raw
    extends_raw=$(vokun::toml::get "meta.extends" "")

    if [[ -z "$extends_raw" ]]; then
        return 0
    fi

    # Build the list of parent names (supports string or newline-separated array)
    local -a parent_names=()
    while IFS= read -r parent; do
        [[ -z "$parent" ]] && continue
        parent_names+=("$parent")
    done <<< "$extends_raw"

    if [[ ${#parent_names[@]} -eq 0 ]]; then
        return 0
    fi

    # Cycle detection
    local child_name
    child_name=$(vokun::bundles::name_from_path "$file")
    for p in "${parent_names[@]}"; do
        if [[ "$p" == "$child_name" ]]; then
            vokun::core::error "Cycle detected in extends: $child_name -> $p"
            return 1
        fi
        if [[ ${#_extends_chain[@]} -gt 0 ]] && vokun::core::in_array "$p" "${_extends_chain[@]}"; then
            vokun::core::error "Cycle detected in extends: ${_extends_chain[*]} -> $child_name -> $p"
            return 1
        fi
    done

    # Save current child data
    local -A child_data=()
    local -A child_keys=()
    local key
    for key in "${!TOML_DATA[@]}"; do
        child_data["$key"]="${TOML_DATA[$key]}"
    done
    for key in "${!TOML_SECTION_KEYS[@]}"; do
        child_keys["$key"]="${TOML_SECTION_KEYS[$key]}"
    done

    # Clear TOML state before merging parents
    unset TOML_DATA TOML_SECTION_KEYS
    declare -gA TOML_DATA
    declare -gA TOML_SECTION_KEYS

    # Merge each parent in order (flat union, last-writer-wins for descriptions)
    for parent_name in "${parent_names[@]}"; do
        local parent_file
        parent_file=$(vokun::bundles::find_by_name "$parent_name" 2>/dev/null) || {
            vokun::core::warn "Parent bundle '$parent_name' not found (referenced by extends)"
            continue
        }

        # Parents cannot themselves have extends (single-level restriction)
        local parent_extends
        # Parse the parent to check for extends without clobbering our merge state
        local -A saved_data=()
        local -A saved_keys=()
        for key in "${!TOML_DATA[@]}"; do
            saved_data["$key"]="${TOML_DATA[$key]}"
        done
        for key in "${!TOML_SECTION_KEYS[@]}"; do
            saved_keys["$key"]="${TOML_SECTION_KEYS[$key]}"
        done

        vokun::toml::parse "$parent_file"
        parent_extends=$(vokun::toml::get "meta.extends" "")
        if [[ -n "$parent_extends" ]]; then
            vokun::core::warn "Parent bundle '$parent_name' itself has extends — ignored (single-level restriction)"
        fi

        # Merge parent packages and select sections into accumulator (last-writer-wins)
        local section
        # Also merge any select.* sections from parent
        local -a parent_sections_list=("packages" "packages.aur" "packages.optional")
        local ps
        for ps in "${TOML_SECTIONS[@]}"; do
            if [[ "$ps" == select.* ]]; then
                parent_sections_list+=("$ps")
            fi
        done
        for section in "${parent_sections_list[@]}"; do
            local parent_section_keys
            parent_section_keys=$(vokun::toml::keys "$section")
            [[ -z "$parent_section_keys" ]] && continue
            while IFS= read -r pkg; do
                [[ -z "$pkg" ]] && continue
                saved_data["${section}.${pkg}"]="${TOML_DATA["${section}.${pkg}"]:-}"
                local existing="${saved_keys[$section]:-}"
                if ! echo "$existing" | grep -qx "$pkg"; then
                    if [[ -n "$existing" ]]; then
                        saved_keys["$section"]+=$'\n'"$pkg"
                    else
                        saved_keys["$section"]="$pkg"
                    fi
                fi
            done <<< "$parent_section_keys"
        done

        # Restore accumulated state
        unset TOML_DATA TOML_SECTION_KEYS
        declare -gA TOML_DATA
        declare -gA TOML_SECTION_KEYS
        for key in "${!saved_data[@]}"; do
            TOML_DATA["$key"]="${saved_data[$key]}"
        done
        for key in "${!saved_keys[@]}"; do
            TOML_SECTION_KEYS["$key"]="${saved_keys[$key]}"
        done
    done

    # Merge child on top: child meta fields take priority
    for key in "${!child_data[@]}"; do
        if [[ "$key" == meta.* ]]; then
            TOML_DATA["$key"]="${child_data[$key]}"
        fi
    done

    # Merge child packages and select sections on top of parent
    local section
    # Include child select.* sections
    local -a child_merge_sections=("packages" "packages.aur" "packages.optional")
    local cs
    for cs in "${!child_keys[@]}"; do
        if [[ "$cs" == select.* ]]; then
            child_merge_sections+=("$cs")
        fi
    done
    for section in "${child_merge_sections[@]}"; do
        local child_section_keys="${child_keys[$section]:-}"
        if [[ -n "$child_section_keys" ]]; then
            while IFS= read -r pkg; do
                [[ -z "$pkg" ]] && continue
                TOML_DATA["${section}.${pkg}"]="${child_data["${section}.${pkg}"]:-}"
                local existing_keys="${TOML_SECTION_KEYS[$section]:-}"
                if ! echo "$existing_keys" | grep -qx "$pkg"; then
                    if [[ -n "$existing_keys" ]]; then
                        TOML_SECTION_KEYS["$section"]+=$'\n'"$pkg"
                    else
                        TOML_SECTION_KEYS["$section"]="$pkg"
                    fi
                fi
            done <<< "$child_section_keys"
        fi
    done

    # Restore child hooks (child hooks replace parent hooks)
    for key in "${!child_data[@]}"; do
        if [[ "$key" == hooks.* ]]; then
            TOML_DATA["$key"]="${child_data[$key]}"
        fi
    done
}

# --- Hook runner ---
# Run hooks of a given type (pre_install, post_install, pre_remove, post_remove)
# Shows commands and requires confirmation before executing.
# Usage: vokun::bundles::_run_hooks "post_install" <dry_run>
vokun::bundles::_run_hooks() {
    local hook_type="$1"
    local dry_run="${2:-false}"

    local hooks
    hooks=$(vokun::toml::get "hooks.${hook_type}" "")
    [[ -z "$hooks" ]] && return 0

    local label="${hook_type//_/-}"

    printf '\n  %s%s hooks:%s\n' "$VOKUN_COLOR_CYAN" "$label" "$VOKUN_COLOR_RESET"
    while IFS= read -r hook_cmd; do
        [[ -z "$hook_cmd" ]] && continue
        printf '    %s\n' "$hook_cmd"
    done <<< "$hooks"

    if [[ "$dry_run" == true ]]; then
        return 0
    fi

    if ! vokun::core::confirm "Run $label hooks?"; then
        vokun::core::log "$label hooks skipped."
        return 0
    fi

    printf '\n%sRunning %s hooks...%s\n' "$VOKUN_COLOR_DIM" "$label" "$VOKUN_COLOR_RESET"
    while IFS= read -r hook_cmd; do
        [[ -z "$hook_cmd" ]] && continue
        vokun::core::show_cmd "$hook_cmd"
        # shellcheck disable=SC2294
        eval "$hook_cmd" || {
            vokun::core::error "Hook failed: $hook_cmd"
            return 1
        }
    done <<< "$hooks"

    return 0
}

# --- Select-one prompts ---

# Prompt user to pick one package from a [select.*] category
# Detects already-installed options, offers Skip.
# Sets VOKUN_SELECT_RESULT to the chosen package name, or "" if skipped.
# Respects VOKUN_SELECT_EXCLUDE and VOKUN_SELECT_ONLY arrays if set.
# Usage: vokun::bundles::_prompt_select "editor" "CLI Editor"
vokun::bundles::_prompt_select() {
    local category="$1"
    local label="$2"
    local section="select.${category}"

    VOKUN_SELECT_RESULT=""

    local keys
    keys=$(vokun::toml::keys "$section")
    [[ -z "$keys" ]] && return 0

    # Build parallel arrays of package names and descriptions
    local -a pkg_names=()
    local -a pkg_descs=()

    while IFS= read -r key; do
        [[ -z "$key" ]] && continue
        # Skip metadata keys
        [[ "$key" == "default" || "$key" == "label" ]] && continue
        # Apply --exclude filter
        if [[ -n "${VOKUN_SELECT_EXCLUDE+x}" && ${#VOKUN_SELECT_EXCLUDE[@]} -gt 0 ]] && vokun::core::in_array "$key" "${VOKUN_SELECT_EXCLUDE[@]}"; then
            continue
        fi
        # Apply --only filter
        if [[ -n "${VOKUN_SELECT_ONLY+x}" && ${#VOKUN_SELECT_ONLY[@]} -gt 0 ]] && ! vokun::core::in_array "$key" "${VOKUN_SELECT_ONLY[@]}"; then
            continue
        fi
        pkg_names+=("$key")
        pkg_descs+=("$(vokun::toml::get "${section}.${key}" "")")
    done <<< "$keys"

    if [[ ${#pkg_names[@]} -eq 0 ]]; then
        return 0
    fi

    # If only one option after filtering, auto-select it
    if [[ ${#pkg_names[@]} -eq 1 ]]; then
        VOKUN_SELECT_RESULT="${pkg_names[0]}"
        printf '\n  %s%s:%s %s%s%s (auto-selected)\n' \
            "$VOKUN_COLOR_BOLD" "$label" "$VOKUN_COLOR_RESET" \
            "$VOKUN_COLOR_CYAN" "${pkg_names[0]}" "$VOKUN_COLOR_RESET"
        return 0
    fi

    printf '\n  %sPick a %s:%s\n' "$VOKUN_COLOR_BOLD" "$label" "$VOKUN_COLOR_RESET"

    if command -v fzf &>/dev/null && [[ "${VOKUN_FZF:-true}" == "true" ]]; then
        # Build fzf input: "name\tdescription [already installed]"
        local fzf_input=""
        local i
        for ((i = 0; i < ${#pkg_names[@]}; i++)); do
            local marker=""
            if vokun::core::is_pkg_installed "${pkg_names[$i]}"; then
                marker=" [already installed]"
            fi
            fzf_input+="${pkg_names[$i]}"$'\t'"${pkg_descs[$i]}${marker}"$'\n'
        done
        fzf_input+="Skip"$'\t'"Keep what you have / install nothing"$'\n'

        local selected
        selected=$(printf '%s' "$fzf_input" | fzf --no-multi --with-nth=1.. --delimiter=$'\t' \
            --prompt="${label}> " \
            --header="Select one (ENTER to confirm)" \
            --no-info 2>/dev/null | cut -f1) || true

        if [[ -n "$selected" && "$selected" != "Skip" ]]; then
            VOKUN_SELECT_RESULT="$selected"
        fi
    else
        # Numbered menu fallback
        local i
        for ((i = 0; i < ${#pkg_names[@]}; i++)); do
            local num=$((i + 1))
            local marker=""
            local arrow="  "
            if vokun::core::is_pkg_installed "${pkg_names[$i]}"; then
                marker=" ${VOKUN_COLOR_GREEN}[already installed]${VOKUN_COLOR_RESET}"
                arrow="${VOKUN_COLOR_GREEN}→ ${VOKUN_COLOR_RESET}"
            fi
            printf '  %s%s%d)%s %-18s %s%s%s%s\n' \
                "$arrow" "$VOKUN_COLOR_BOLD" "$num" "$VOKUN_COLOR_RESET" \
                "${pkg_names[$i]}" \
                "$VOKUN_COLOR_DIM" "${pkg_descs[$i]}" "$VOKUN_COLOR_RESET" \
                "$marker"
        done
        local skip_num=$(( ${#pkg_names[@]} + 1 ))
        printf '    %s%d)%s Skip\n' "$VOKUN_COLOR_BOLD" "$skip_num" "$VOKUN_COLOR_RESET"

        printf '\n  %s> ' "$VOKUN_COLOR_RESET"
        local reply
        read -r reply

        if [[ "$reply" =~ ^[0-9]+$ ]] && (( reply >= 1 && reply <= ${#pkg_names[@]} )); then
            VOKUN_SELECT_RESULT="${pkg_names[$((reply - 1))]}"
        fi
    fi

    if [[ -n "$VOKUN_SELECT_RESULT" ]]; then
        printf '  %s→ %s%s\n' "$VOKUN_COLOR_GREEN" "$VOKUN_SELECT_RESULT" "$VOKUN_COLOR_RESET"
    else
        printf '  %s→ Skipped%s\n' "$VOKUN_COLOR_DIM" "$VOKUN_COLOR_RESET"
    fi
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

    vokun::bundles::load_with_extends "$file"

    local description version tags_str extends
    description=$(vokun::toml::get "meta.description" "No description")
    version=$(vokun::toml::get "meta.version" "")
    tags_str=$(vokun::toml::get "meta.tags" "")
    extends=$(vokun::toml::get "meta.extends" "")

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

    if [[ -n "$extends" ]]; then
        local extends_display
        extends_display=$(echo "$extends" | tr '\n' ', ' | sed 's/,$//')
        printf '%sExtends: %s%s\n' "$VOKUN_COLOR_DIM" "$extends_display" "$VOKUN_COLOR_RESET"
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

    # Select-one categories
    local -a info_select_cats
    mapfile -t info_select_cats < <(vokun::toml::subsections "select")
    if [[ ${#info_select_cats[@]} -gt 0 ]]; then
        local sel_cat
        for sel_cat in "${info_select_cats[@]}"; do
            [[ -z "$sel_cat" ]] && continue
            local sel_label sel_section sel_keys
            sel_label=$(vokun::toml::get "select.${sel_cat}.label" "$sel_cat")
            sel_section="select.${sel_cat}"
            sel_keys=$(vokun::toml::keys "$sel_section")
            [[ -z "$sel_keys" ]] && continue

            # Check if user already has a selection for this bundle
            local current_sel=""
            if vokun::state::is_installed "$name"; then
                current_sel=$(vokun::state::get_selection "$name" "$sel_cat")
            fi

            printf '\n  %sSelect one — %s:%s\n' "$VOKUN_COLOR_MAGENTA" "$sel_label" "$VOKUN_COLOR_RESET"
            while IFS= read -r pkg; do
                [[ -z "$pkg" || "$pkg" == "default" || "$pkg" == "label" ]] && continue
                local desc status="" selected_marker=""
                desc=$(vokun::toml::get "${sel_section}.${pkg}")
                if vokun::core::is_pkg_installed "$pkg"; then
                    status="${VOKUN_COLOR_GREEN} [installed]${VOKUN_COLOR_RESET}"
                fi
                if [[ "$pkg" == "$current_sel" ]]; then
                    selected_marker="${VOKUN_COLOR_CYAN} ★${VOKUN_COLOR_RESET}"
                fi
                printf '    %-25s %s%s%s\n' "$pkg" "${VOKUN_COLOR_DIM}${desc}${VOKUN_COLOR_RESET}" "$status" "$selected_marker"
            done <<< "$sel_keys"
        done
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

        # Check package names (including select.* categories)
        local all_keys=""
        all_keys+=$(vokun::toml::keys "packages")
        all_keys+=$'\n'$(vokun::toml::keys "packages.aur")
        all_keys+=$'\n'$(vokun::toml::keys "packages.optional")
        local _sel_cat
        while IFS= read -r _sel_cat; do
            [[ -n "$_sel_cat" ]] && all_keys+=$'\n'$(vokun::toml::keys "select.${_sel_cat}")
        done < <(vokun::toml::subsections "select")

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
    local name=""
    local dry_run=false
    local pick_mode=false
    local exclude_list=""
    local only_list=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) dry_run=true; shift ;;
            --pick) pick_mode=true; shift ;;
            --exclude)
                exclude_list="${2:-}"
                shift 2 || { vokun::core::error "--exclude requires a comma-separated package list"; return 1; }
                ;;
            --only)
                only_list="${2:-}"
                shift 2 || { vokun::core::error "--only requires a comma-separated package list"; return 1; }
                ;;
            *) [[ -z "$name" ]] && name="$1"; shift ;;
        esac
    done

    if [[ -z "$name" ]]; then
        vokun::core::error "Usage: vokun install <bundle> [--pick] [--exclude pkg,...] [--only pkg,...] [--dry-run]"
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

    vokun::bundles::load_with_extends "$file"

    local description
    description=$(vokun::toml::get "meta.description" "")

    printf '\n%sInstalling bundle: %s%s\n' "$VOKUN_COLOR_BOLD" "$name" "$VOKUN_COLOR_RESET"
    [[ -n "$description" ]] && printf '%s\n' "$description"
    printf '%s\n' "$(printf '%.0s─' {1..50})"

    # Build exclude/only arrays for filtering
    local -a exclude_arr=() only_arr=()
    if [[ -n "$exclude_list" ]]; then
        IFS=',' read -ra exclude_arr <<< "$exclude_list"
    fi
    if [[ -n "$only_list" ]]; then
        IFS=',' read -ra only_arr <<< "$only_list"
    fi

    # Collect packages (applying --exclude and --only during collection)
    local -a repo_packages=()
    local -a aur_packages=()
    local -a optional_packages=()
    local -a already_installed=()
    local -a skipped_by_filter=()
    local -a to_install=()

    # Regular packages
    local pkg_keys
    pkg_keys=$(vokun::toml::keys "packages")
    if [[ -n "$pkg_keys" ]]; then
        while IFS= read -r pkg; do
            [[ -z "$pkg" ]] && continue
            # Apply --exclude
            if [[ ${#exclude_arr[@]} -gt 0 ]] && vokun::core::in_array "$pkg" "${exclude_arr[@]}"; then
                skipped_by_filter+=("$pkg")
                continue
            fi
            # Apply --only
            if [[ ${#only_arr[@]} -gt 0 ]] && ! vokun::core::in_array "$pkg" "${only_arr[@]}"; then
                skipped_by_filter+=("$pkg")
                continue
            fi
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
            # Apply --exclude
            if [[ ${#exclude_arr[@]} -gt 0 ]] && vokun::core::in_array "$pkg" "${exclude_arr[@]}"; then
                skipped_by_filter+=("$pkg")
                continue
            fi
            # Apply --only
            if [[ ${#only_arr[@]} -gt 0 ]] && ! vokun::core::in_array "$pkg" "${only_arr[@]}"; then
                skipped_by_filter+=("$pkg")
                continue
            fi
            if vokun::core::is_pkg_installed "$pkg"; then
                already_installed+=("$pkg")
            else
                aur_packages+=("$pkg")
            fi
        done <<< "$aur_keys"
    fi

    # --- Filtering: --pick, --exclude, --only ---

    # Build the full candidate list (repo + aur, not yet installed)
    local -a all_candidates=("${repo_packages[@]}" "${aur_packages[@]}")

    # --pick: interactive selection via fzf or numbered menu
    if [[ "$pick_mode" == true && ${#all_candidates[@]} -gt 0 ]]; then
        local -a picked=()

        if command -v fzf &>/dev/null && [[ "${VOKUN_FZF:-true}" == "true" ]]; then
            vokun::core::info "Select packages to install (TAB to toggle, ENTER to confirm)"
            mapfile -t picked < <(
                for pkg in "${all_candidates[@]}"; do
                    local section="packages"
                    vokun::core::in_array "$pkg" "${aur_packages[@]}" && section="packages.aur"
                    local desc
                    desc=$(vokun::toml::get "${section}.${pkg}")
                    printf '%s\t%s\n' "$pkg" "$desc"
                done | fzf --multi --with-nth=1.. --delimiter='\t' \
                    --prompt="Pick packages> " \
                    --header="TAB to select, ENTER to confirm" | cut -f1
            )
        else
            # Numbered menu fallback
            printf '\n  %sSelect packages to install:%s\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET"
            local i=1
            for pkg in "${all_candidates[@]}"; do
                printf '    %s%d)%s %s\n' "$VOKUN_COLOR_BOLD" "$i" "$VOKUN_COLOR_RESET" "$pkg"
                ((i++))
            done
            printf '\n  Enter numbers separated by spaces (e.g., 1 3 5): '
            local selection
            read -r selection
            # shellcheck disable=SC2086
            for num in $selection; do
                if [[ "$num" =~ ^[0-9]+$ ]] && (( num >= 1 && num <= ${#all_candidates[@]} )); then
                    picked+=("${all_candidates[$((num - 1))]}")
                fi
            done
        fi

        if [[ ${#picked[@]} -eq 0 ]]; then
            vokun::core::log "No packages selected. Installation cancelled."
            return 1
        fi

        # Rebuild repo_packages and aur_packages from picked list
        local -a new_repo=() new_aur=()
        for pkg in "${picked[@]}"; do
            if vokun::core::in_array "$pkg" "${aur_packages[@]}"; then
                new_aur+=("$pkg")
            else
                new_repo+=("$pkg")
            fi
        done
        repo_packages=("${new_repo[@]}")
        aur_packages=("${new_aur[@]}")
    fi

    # Show what was filtered out
    if [[ ${#skipped_by_filter[@]} -gt 0 ]]; then
        printf '\n  %sSkipped:%s %s\n' "$VOKUN_COLOR_DIM" "$VOKUN_COLOR_RESET" "${skipped_by_filter[*]}"
    fi

    # Process [select.*] sections — pick-one categories
    local -a select_pairs=()
    local -a select_packages=()
    local -a select_categories
    mapfile -t select_categories < <(vokun::toml::subsections "select")

    # Pass --exclude/--only filters to select prompts
    # shellcheck disable=SC2034
    VOKUN_SELECT_EXCLUDE=("${exclude_arr[@]}")
    # shellcheck disable=SC2034
    VOKUN_SELECT_ONLY=("${only_arr[@]}")

    if [[ ${#select_categories[@]} -gt 0 && "$dry_run" == false ]]; then
        printf '\n%s\n' "$(printf '%.0s─' {1..50})"
        vokun::core::info "Choose your preferred tools:"

        local sel_cat
        for sel_cat in "${select_categories[@]}"; do
            [[ -z "$sel_cat" ]] && continue
            local sel_label
            sel_label=$(vokun::toml::get "select.${sel_cat}.label" "$sel_cat")
            vokun::bundles::_prompt_select "$sel_cat" "$sel_label"
            if [[ -n "$VOKUN_SELECT_RESULT" ]]; then
                select_pairs+=("${sel_cat}=${VOKUN_SELECT_RESULT}")
                if ! vokun::core::is_pkg_installed "$VOKUN_SELECT_RESULT"; then
                    select_packages+=("$VOKUN_SELECT_RESULT")
                    repo_packages+=("$VOKUN_SELECT_RESULT")
                else
                    already_installed+=("$VOKUN_SELECT_RESULT")
                fi
            fi
        done
        printf '\n'
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

        if [[ ${#opt_list[@]} -gt 0 && "$dry_run" == false ]]; then
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

    # Conflict pre-flight check
    if [[ ${#repo_packages[@]} -gt 0 ]]; then
        local -a conflicts=()
        local pkg
        for pkg in "${repo_packages[@]}"; do
            local conflict_info
            conflict_info=$(pacman -Si "$pkg" 2>/dev/null | sed -n 's/^Conflicts With *: *//p' || true)
            if [[ -n "$conflict_info" && "$conflict_info" != "None" ]]; then
                # Check if any conflicting package is actually installed
                local conflict_pkg
                for conflict_pkg in $conflict_info; do
                    # Strip version constraints (e.g., "foo>=1.0" -> "foo")
                    conflict_pkg="${conflict_pkg%%[<>=]*}"
                    if vokun::core::is_pkg_installed "$conflict_pkg"; then
                        conflicts+=("$pkg conflicts with $conflict_pkg (installed)")
                    fi
                done
            fi
        done

        if [[ ${#conflicts[@]} -gt 0 ]]; then
            printf '\n  %sPackage conflicts detected:%s\n' "$VOKUN_COLOR_RED" "$VOKUN_COLOR_RESET"
            for c in "${conflicts[@]}"; do
                printf '    %s\n' "$c"
            done
            printf '\n'
            vokun::core::warn "Pacman will ask to resolve these during installation."
            printf '\n'
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

    # Dry-run: show what would happen and exit
    if [[ "$dry_run" == true ]]; then
        printf '  %s[DRY RUN] Commands that would be executed:%s\n\n' "$VOKUN_COLOR_YELLOW" "$VOKUN_COLOR_RESET"
        local helper
        helper=$(vokun::core::get_aur_helper)
        if [[ ${#repo_packages[@]} -gt 0 ]]; then
            local cmd="${helper:-pacman}"
            printf '    %s -S --needed %s\n' "$cmd" "${repo_packages[*]}"
        fi
        if [[ ${#aur_packages[@]} -gt 0 && -n "$helper" ]]; then
            printf '    %s -S --needed %s\n' "$helper" "${aur_packages[*]}"
        fi
        printf '\n  %sNo changes were made.%s\n' "$VOKUN_COLOR_DIM" "$VOKUN_COLOR_RESET"
        return 0
    fi

    # Confirm
    if ! vokun::core::confirm "Proceed with installation?"; then
        vokun::core::log "Installation cancelled."
        return 1
    fi

    # Run pre-install hooks
    if ! vokun::bundles::_run_hooks "pre_install" false; then
        vokun::core::error "Pre-install hook failed. Installation aborted."
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

        # Show PKGBUILDs before AUR install if configured
        if [[ "${VOKUN_AUR_SHOW_PKGBUILD:-false}" == "true" ]]; then
            local aur_pkg
            for aur_pkg in "${aur_packages[@]}"; do
                vokun::aur::diff "$aur_pkg" 2>/dev/null || true
                printf '\n'
            done
        fi

        vokun::core::show_cmd "$aur_helper -S --needed ${aur_packages[*]}"
        "$aur_helper" -S --needed "${aur_packages[@]}" || install_failed=true
    fi

    if [[ "$install_failed" == true ]]; then
        vokun::core::error "Some packages failed to install"
        return 1
    fi

    # Run post-install hooks
    vokun::bundles::_run_hooks "post_install" false

    # Update state — track installed and skipped packages
    local all_pkgs
    all_pkgs=$(printf '%s ' "${already_installed[@]}" "${repo_packages[@]}" "${aur_packages[@]}")

    # Build skipped list from filtered + pick-mode unselected packages
    local skipped_pkgs=""
    skipped_pkgs=$(printf '%s ' "${skipped_by_filter[@]}")
    # In pick mode, anything from candidates not picked is also skipped
    if [[ "$pick_mode" == true ]]; then
        for pkg in "${all_candidates[@]}"; do
            if ! vokun::core::in_array "$pkg" "${repo_packages[@]}" && \
               ! vokun::core::in_array "$pkg" "${aur_packages[@]}"; then
                skipped_pkgs+="$pkg "
            fi
        done
    fi

    vokun::state::add_bundle "$name" "$all_pkgs" "$skipped_pkgs" "default"

    # Save selections if any were made
    if [[ ${#select_pairs[@]} -gt 0 ]]; then
        vokun::state::save_selections "$name" "${select_pairs[@]}"
    fi

    # Log the action
    local installed_list
    installed_list=$(printf '%s ' "${repo_packages[@]}" "${aur_packages[@]}")
    vokun::core::log_action "bundle-install" "$name" "$installed_list"

    printf '\n'
    vokun::core::success "Bundle '$name' installed successfully!"
}

# --- vokun remove ---

vokun::bundles::remove() {
    local name=""
    local dry_run=false

    for arg in "$@"; do
        case "$arg" in
            --dry-run) dry_run=true ;;
            *) [[ -z "$name" ]] && name="$arg" ;;
        esac
    done

    if [[ -z "$name" ]]; then
        vokun::core::error "Usage: vokun remove <bundle> [--dry-run]"
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

    # Dry-run: show what would happen and exit
    if [[ "$dry_run" == true ]]; then
        printf '  %s[DRY RUN] Command that would be executed:%s\n\n' "$VOKUN_COLOR_YELLOW" "$VOKUN_COLOR_RESET"
        printf '    sudo pacman -Rns %s\n' "${unique_pkgs[*]}"
        printf '\n  %sNo changes were made.%s\n' "$VOKUN_COLOR_DIM" "$VOKUN_COLOR_RESET"
        return 0
    fi

    if ! vokun::core::confirm "Remove ${#unique_pkgs[@]} package(s)?"; then
        vokun::core::log "Removal cancelled."
        return 1
    fi

    # Load bundle TOML for hooks
    local file
    file=$(vokun::bundles::find_by_name "$name" 2>/dev/null)
    if [[ -n "$file" ]]; then
        vokun::bundles::load_with_extends "$file"
    fi

    # Run pre-remove hooks
    if ! vokun::bundles::_run_hooks "pre_remove" false; then
        vokun::core::error "Pre-remove hook failed. Removal aborted."
        return 1
    fi

    vokun::core::run_pacman_only "-Rns" "${unique_pkgs[@]}" || {
        vokun::core::error "Some packages failed to remove"
        return 1
    }

    # Run post-remove hooks
    vokun::bundles::_run_hooks "post_remove" false

    # Log the action
    vokun::core::log_action "bundle-remove" "$name" "${unique_pkgs[*]}"

    vokun::state::remove_bundle "$name"
    printf '\n'
    vokun::core::success "Bundle '$name' removed!"
}

# --- vokun select ---

# Change select-one choices for an installed bundle
vokun::bundles::select() {
    local name="${1:-}"
    # shellcheck disable=SC2034
    VOKUN_SELECT_EXCLUDE=()
    # shellcheck disable=SC2034
    VOKUN_SELECT_ONLY=()

    if [[ -z "$name" ]]; then
        vokun::core::error "Usage: vokun select <bundle>"
        return 1
    fi

    if ! vokun::state::is_installed "$name"; then
        vokun::core::error "Bundle '$name' is not installed"
        vokun::core::log "Install it first with 'vokun install $name'."
        return 1
    fi

    local file
    file=$(vokun::bundles::find_by_name "$name") || {
        vokun::core::error "Bundle definition not found: $name"
        return 1
    }

    vokun::bundles::load_with_extends "$file"

    local -a select_categories
    mapfile -t select_categories < <(vokun::toml::subsections "select")

    if [[ ${#select_categories[@]} -eq 0 ]]; then
        vokun::core::info "Bundle '$name' has no select-one categories."
        return 0
    fi

    printf '\n%sChange selections for: %s%s\n' "$VOKUN_COLOR_BOLD" "$name" "$VOKUN_COLOR_RESET"
    printf '%s\n' "$(printf '%.0s─' {1..50})"

    # Show current selections
    local -a current_sels
    mapfile -t current_sels < <(vokun::state::get_selections "$name")
    if [[ ${#current_sels[@]} -gt 0 ]]; then
        printf '\n  %sCurrent selections:%s\n' "$VOKUN_COLOR_DIM" "$VOKUN_COLOR_RESET"
        local sel_line
        for sel_line in "${current_sels[@]}"; do
            [[ -z "$sel_line" ]] && continue
            local sel_cat="${sel_line%%=*}"
            local sel_pkg="${sel_line#*=}"
            local sel_label
            sel_label=$(vokun::toml::get "select.${sel_cat}.label" "$sel_cat")
            printf '    %s: %s%s%s\n' "$sel_label" "$VOKUN_COLOR_CYAN" "$sel_pkg" "$VOKUN_COLOR_RESET"
        done
    fi

    printf '\n'

    local -a new_packages=()
    local -a old_packages=()

    local sel_cat
    for sel_cat in "${select_categories[@]}"; do
        [[ -z "$sel_cat" ]] && continue
        local sel_label
        sel_label=$(vokun::toml::get "select.${sel_cat}.label" "$sel_cat")

        local old_choice
        old_choice=$(vokun::state::get_selection "$name" "$sel_cat")

        vokun::bundles::_prompt_select "$sel_cat" "$sel_label"

        local new_choice="$VOKUN_SELECT_RESULT"

        if [[ -z "$new_choice" ]]; then
            # Skipped — keep old selection
            continue
        fi

        if [[ "$new_choice" == "$old_choice" ]]; then
            vokun::core::log "  (unchanged)"
            continue
        fi

        # Track old package for removal (if it was installed by us)
        if [[ -n "$old_choice" ]]; then
            old_packages+=("$old_choice")
        fi

        # Track new package for installation
        if ! vokun::core::is_pkg_installed "$new_choice"; then
            new_packages+=("$new_choice")
        fi

        # Update state immediately
        vokun::state::update_selection "$name" "$sel_cat" "$new_choice"

        # Also update the bundle's package list in state
        local tmp
        tmp=$(mktemp)
        # Add new choice to packages, remove old choice
        if [[ -n "$old_choice" ]]; then
            jq --arg b "$name" --arg old "$old_choice" --arg new "$new_choice" \
                '.installed_bundles[$b].packages = ([.installed_bundles[$b].packages[] | select(. != $old)] + [$new] | unique)' \
                "$VOKUN_STATE_FILE" > "$tmp" && mv "$tmp" "$VOKUN_STATE_FILE"
        else
            jq --arg b "$name" --arg new "$new_choice" \
                '.installed_bundles[$b].packages = (.installed_bundles[$b].packages + [$new] | unique)' \
                "$VOKUN_STATE_FILE" > "$tmp" && mv "$tmp" "$VOKUN_STATE_FILE"
        fi
    done

    # Install new packages
    if [[ ${#new_packages[@]} -gt 0 ]]; then
        printf '\n'
        vokun::core::info "Installing: ${new_packages[*]}"
        vokun::core::run_pacman "-S" "--needed" "${new_packages[@]}" || {
            vokun::core::error "Failed to install new selections"
            return 1
        }
    fi

    # Offer to remove old packages (only if not shared and not the same as new)
    local -a removable=()
    local old_pkg
    for old_pkg in "${old_packages[@]}"; do
        [[ -z "$old_pkg" ]] && continue
        # Don't remove if it's also a new selection
        if vokun::core::in_array "$old_pkg" "${new_packages[@]+"${new_packages[@]}"}"; then
            continue
        fi
        # Don't remove if shared with other bundles
        local shared
        shared=$(vokun::state::get_shared_packages "$name" "$old_pkg")
        if [[ -n "$shared" ]]; then
            continue
        fi
        if vokun::core::is_pkg_installed "$old_pkg"; then
            removable+=("$old_pkg")
        fi
    done

    if [[ ${#removable[@]} -gt 0 ]]; then
        printf '\n'
        printf '  %sOld selections still installed:%s %s\n' "$VOKUN_COLOR_DIM" "$VOKUN_COLOR_RESET" "${removable[*]}"
        printf '  Remove them? [y/N] '
        local reply
        read -r reply
        if [[ "$reply" =~ ^[yY] ]]; then
            vokun::core::run_pacman_only "-Rns" "${removable[@]}" || true
        fi
    fi

    vokun::core::log_action "bundle-select" "$name" "changed selections"

    printf '\n'
    vokun::core::success "Selections updated for '$name'!"
}
