#!/usr/bin/env bash
# shellcheck disable=SC2034
# vokun - Export/Import
# Export and import custom bundles, state, and config

# --- Export ---

vokun::export::run() {
    local output_file="./vokun-export.tar.gz"
    local json_mode=false
    local args=()

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                json_mode=true
                shift
                ;;
            -*)
                vokun::core::error "Unknown flag: $1"
                return 1
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done

    # Optional filename override
    if [[ ${#args[@]} -gt 0 ]]; then
        output_file="${args[0]}"
    elif [[ "$json_mode" == true && "$output_file" == "./vokun-export.tar.gz" ]]; then
        output_file="./vokun-export.json"
    fi

    local custom_dir="${VOKUN_CONFIG_DIR}/bundles/custom"
    local state_file="${VOKUN_CONFIG_DIR}/state.json"
    local config_file="${VOKUN_CONFIG_DIR}/vokun.conf"

    # Collect files to export
    local -a export_files=()
    local -a export_labels=()

    if [[ -d "$custom_dir" ]]; then
        local -a bundle_files=()
        while IFS= read -r -d '' f; do
            bundle_files+=("$f")
        done < <(find "$custom_dir" -maxdepth 1 -type f -print0 2>/dev/null)

        if [[ ${#bundle_files[@]} -gt 0 ]]; then
            for f in "${bundle_files[@]}"; do
                export_files+=("$f")
                export_labels+=("bundle: $(basename "$f")")
            done
        fi
    fi

    if [[ -f "$state_file" ]]; then
        export_files+=("$state_file")
        export_labels+=("state: state.json")
    fi

    if [[ -f "$config_file" ]]; then
        export_files+=("$config_file")
        export_labels+=("config: vokun.conf")
    fi

    if [[ ${#export_files[@]} -eq 0 ]]; then
        vokun::core::warn "Nothing to export — no custom bundles, state, or config found."
        return 1
    fi

    # Show what's being exported
    vokun::core::info "Exporting vokun data:"
    local label
    for label in "${export_labels[@]}"; do
        vokun::core::log "  ${VOKUN_COLOR_DIM}•${VOKUN_COLOR_RESET} ${label}"
    done
    vokun::core::log ""

    if [[ "$json_mode" == true ]]; then
        vokun::export::_export_json "$output_file" "$state_file" "$config_file" "$custom_dir"
    else
        vokun::export::_export_tar "$output_file" "${export_files[@]}"
    fi
}

vokun::export::_export_tar() {
    local output_file="$1"
    shift
    local -a files=("$@")

    local tmp_dir
    tmp_dir=$(mktemp -d)
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp_dir'" RETURN

    # Stage files with directory structure
    mkdir -p "${tmp_dir}/bundles/custom"

    local f
    for f in "${files[@]}"; do
        local basename
        basename=$(basename "$f")
        case "$f" in
            */bundles/custom/*)
                cp "$f" "${tmp_dir}/bundles/custom/${basename}"
                ;;
            */state.json)
                cp "$f" "${tmp_dir}/state.json"
                ;;
            */vokun.conf)
                cp "$f" "${tmp_dir}/vokun.conf"
                ;;
        esac
    done

    vokun::core::show_cmd "tar czf ${output_file} -C ${tmp_dir} ."
    if tar czf "$output_file" -C "$tmp_dir" .; then
        local size
        size=$(du -h "$output_file" | cut -f1)
        vokun::core::success "Exported to ${VOKUN_COLOR_BOLD}${output_file}${VOKUN_COLOR_RESET} (${size})"
    else
        vokun::core::error "Failed to create archive."
        return 1
    fi
}

vokun::export::_export_json() {
    local output_file="$1"
    local state_file="$2"
    local config_file="$3"
    local custom_dir="$4"

    if ! command -v jq &>/dev/null; then
        vokun::core::error "jq is required for JSON export. Install it with: sudo pacman -S jq"
        return 1
    fi

    # Build JSON: merge state + config contents + bundle contents
    local state_json='{}'
    if [[ -f "$state_file" ]]; then
        state_json=$(cat "$state_file")
    fi

    local config_content=""
    if [[ -f "$config_file" ]]; then
        config_content=$(cat "$config_file")
    fi

    local bundles_json='{}'
    if [[ -d "$custom_dir" ]]; then
        local -a bundle_files=()
        while IFS= read -r -d '' f; do
            bundle_files+=("$f")
        done < <(find "$custom_dir" -maxdepth 1 -type f -print0 2>/dev/null)

        if [[ ${#bundle_files[@]} -gt 0 ]]; then
            bundles_json='{'
            local first=true
            local f
            for f in "${bundle_files[@]}"; do
                local bname
                bname=$(basename "$f")
                local bcontent
                bcontent=$(cat "$f")
                if [[ "$first" == true ]]; then
                    first=false
                else
                    bundles_json+=','
                fi
                bundles_json+=$(jq -n --arg name "$bname" --arg content "$bcontent" '{($name): $content}')
            done
            bundles_json+='}'
            # Merge the individual objects
            bundles_json=$(echo "$bundles_json" | jq -s 'add')
        fi
    fi

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    vokun::core::show_cmd "jq -n ... > ${output_file}"
    if jq -n \
        --arg ts "$timestamp" \
        --argjson state "$state_json" \
        --arg config "$config_content" \
        --argjson bundles "$bundles_json" \
        '{
            export_version: "1.0.0",
            exported_at: $ts,
            state: $state,
            config: $config,
            bundles: $bundles
        }' > "$output_file"; then
        local size
        size=$(du -h "$output_file" | cut -f1)
        vokun::core::success "Exported to ${VOKUN_COLOR_BOLD}${output_file}${VOKUN_COLOR_RESET} (${size})"
    else
        vokun::core::error "Failed to create JSON export."
        return 1
    fi
}

# --- Import ---

vokun::export::import() {
    local input_file=""
    local dry_run=false
    local args=()

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry)
                dry_run=true
                shift
                ;;
            -*)
                vokun::core::error "Unknown flag: $1"
                return 1
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done

    if [[ ${#args[@]} -eq 0 ]]; then
        vokun::core::error "Usage: vokun import <file> [--dry]"
        return 1
    fi

    input_file="${args[0]}"

    if [[ ! -f "$input_file" ]]; then
        vokun::core::error "File not found: ${input_file}"
        return 1
    fi

    # Auto-detect format
    case "$input_file" in
        *.tar.gz|*.tgz)
            vokun::export::_import_tar "$input_file" "$dry_run"
            ;;
        *.json)
            vokun::export::_import_json "$input_file" "$dry_run"
            ;;
        *)
            vokun::core::error "Unknown file format. Expected .tar.gz or .json"
            return 1
            ;;
    esac
}

vokun::export::_import_tar() {
    local input_file="$1"
    local dry_run="$2"
    local custom_dir="${VOKUN_CONFIG_DIR}/bundles/custom"

    local tmp_dir
    tmp_dir=$(mktemp -d)
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp_dir'" RETURN

    vokun::core::show_cmd "tar xzf ${input_file} -C ${tmp_dir}"
    if ! tar xzf "$input_file" -C "$tmp_dir"; then
        vokun::core::error "Failed to extract archive."
        return 1
    fi

    vokun::core::info "Archive contents:"

    # Show bundles
    local -a imported_bundles=()
    local -a conflict_bundles=()
    if [[ -d "${tmp_dir}/bundles/custom" ]]; then
        local f
        for f in "${tmp_dir}/bundles/custom/"*; do
            [[ -f "$f" ]] || continue
            local bname
            bname=$(basename "$f")
            imported_bundles+=("$bname")
            if [[ -f "${custom_dir}/${bname}" ]]; then
                conflict_bundles+=("$bname")
                vokun::core::log "  ${VOKUN_COLOR_YELLOW}⚠${VOKUN_COLOR_RESET} bundle: ${bname} ${VOKUN_COLOR_YELLOW}(already exists)${VOKUN_COLOR_RESET}"
            else
                vokun::core::log "  ${VOKUN_COLOR_GREEN}+${VOKUN_COLOR_RESET} bundle: ${bname}"
            fi
        done
    fi

    if [[ -f "${tmp_dir}/state.json" ]]; then
        vokun::core::log "  ${VOKUN_COLOR_DIM}•${VOKUN_COLOR_RESET} state: state.json"
    fi

    if [[ -f "${tmp_dir}/vokun.conf" ]]; then
        vokun::core::log "  ${VOKUN_COLOR_DIM}•${VOKUN_COLOR_RESET} config: vokun.conf"
    fi

    vokun::core::log ""

    if [[ ${#conflict_bundles[@]} -gt 0 ]]; then
        vokun::core::warn "${#conflict_bundles[@]} bundle(s) already exist and will be overwritten."
    fi

    if [[ "$dry_run" == true ]]; then
        vokun::core::info "Dry run — no changes made."
        return 0
    fi

    # Confirm import
    if ! vokun::core::confirm "Import these files?"; then
        vokun::core::log "Import cancelled."
        return 0
    fi

    # Copy bundles
    mkdir -p "$custom_dir"
    if [[ -d "${tmp_dir}/bundles/custom" ]]; then
        local f
        for f in "${tmp_dir}/bundles/custom/"*; do
            [[ -f "$f" ]] || continue
            cp "$f" "$custom_dir/"
        done
        vokun::core::success "Imported ${#imported_bundles[@]} bundle(s) to ${custom_dir}"
    fi

    # Merge state
    if [[ -f "${tmp_dir}/state.json" ]]; then
        vokun::export::_merge_state "${tmp_dir}/state.json"
    fi

    # Copy config if it doesn't exist
    if [[ -f "${tmp_dir}/vokun.conf" ]]; then
        if [[ -f "${VOKUN_CONFIG_DIR}/vokun.conf" ]]; then
            vokun::core::warn "Config file already exists — skipping (use manual merge)."
        else
            cp "${tmp_dir}/vokun.conf" "${VOKUN_CONFIG_DIR}/vokun.conf"
            vokun::core::success "Imported config file."
        fi
    fi

    # Offer to install packages
    if [[ ${#imported_bundles[@]} -gt 0 ]]; then
        vokun::core::log ""
        printf 'Install packages from imported bundles now? [y/N] '
        local reply
        read -r reply
        case "$reply" in
            [yY]|[yY][eE][sS])
                local bname
                for bname in "${imported_bundles[@]}"; do
                    local bundle_name="${bname%.*}"  # strip extension
                    vokun::core::info "Installing bundle: ${bundle_name}"
                    vokun install "$bundle_name" || true
                done
                ;;
            *)
                vokun::core::log "Skipped. Run 'vokun install <bundle>' to install later."
                ;;
        esac
    fi
}

vokun::export::_import_json() {
    local input_file="$1"
    local dry_run="$2"
    local custom_dir="${VOKUN_CONFIG_DIR}/bundles/custom"

    if ! command -v jq &>/dev/null; then
        vokun::core::error "jq is required for JSON import. Install it with: sudo pacman -S jq"
        return 1
    fi

    # Validate JSON
    if ! jq empty "$input_file" 2>/dev/null; then
        vokun::core::error "Invalid JSON file: ${input_file}"
        return 1
    fi

    vokun::core::info "JSON export contents:"

    # Show bundles
    local -a imported_bundles=()
    local -a conflict_bundles=()
    local -a bundle_names=()
    while IFS= read -r bname; do
        [[ -z "$bname" ]] && continue
        bundle_names+=("$bname")
    done < <(jq -r '.bundles // {} | keys[]' "$input_file" 2>/dev/null)

    local bname
    for bname in "${bundle_names[@]}"; do
        imported_bundles+=("$bname")
        if [[ -f "${custom_dir}/${bname}" ]]; then
            conflict_bundles+=("$bname")
            vokun::core::log "  ${VOKUN_COLOR_YELLOW}⚠${VOKUN_COLOR_RESET} bundle: ${bname} ${VOKUN_COLOR_YELLOW}(already exists)${VOKUN_COLOR_RESET}"
        else
            vokun::core::log "  ${VOKUN_COLOR_GREEN}+${VOKUN_COLOR_RESET} bundle: ${bname}"
        fi
    done

    local has_state
    has_state=$(jq -r 'if .state != null and .state != {} then "yes" else "no" end' "$input_file")
    if [[ "$has_state" == "yes" ]]; then
        vokun::core::log "  ${VOKUN_COLOR_DIM}•${VOKUN_COLOR_RESET} state: state.json"
    fi

    local has_config
    has_config=$(jq -r 'if .config != null and .config != "" then "yes" else "no" end' "$input_file")
    if [[ "$has_config" == "yes" ]]; then
        vokun::core::log "  ${VOKUN_COLOR_DIM}•${VOKUN_COLOR_RESET} config: vokun.conf"
    fi

    vokun::core::log ""

    if [[ ${#conflict_bundles[@]} -gt 0 ]]; then
        vokun::core::warn "${#conflict_bundles[@]} bundle(s) already exist and will be overwritten."
    fi

    if [[ "$dry_run" == true ]]; then
        vokun::core::info "Dry run — no changes made."
        return 0
    fi

    # Confirm import
    if ! vokun::core::confirm "Import these files?"; then
        vokun::core::log "Import cancelled."
        return 0
    fi

    # Extract and write bundles
    mkdir -p "$custom_dir"
    for bname in "${imported_bundles[@]}"; do
        jq -r --arg name "$bname" '.bundles[$name]' "$input_file" > "${custom_dir}/${bname}"
    done
    if [[ ${#imported_bundles[@]} -gt 0 ]]; then
        vokun::core::success "Imported ${#imported_bundles[@]} bundle(s) to ${custom_dir}"
    fi

    # Merge state
    if [[ "$has_state" == "yes" ]]; then
        local tmp_state
        tmp_state=$(mktemp)
        jq '.state' "$input_file" > "$tmp_state"
        vokun::export::_merge_state "$tmp_state"
        rm -f "$tmp_state"
    fi

    # Write config
    if [[ "$has_config" == "yes" ]]; then
        if [[ -f "${VOKUN_CONFIG_DIR}/vokun.conf" ]]; then
            vokun::core::warn "Config file already exists — skipping (use manual merge)."
        else
            jq -r '.config' "$input_file" > "${VOKUN_CONFIG_DIR}/vokun.conf"
            vokun::core::success "Imported config file."
        fi
    fi

    # Offer to install packages
    if [[ ${#imported_bundles[@]} -gt 0 ]]; then
        vokun::core::log ""
        printf 'Install packages from imported bundles now? [y/N] '
        local reply
        read -r reply
        case "$reply" in
            [yY]|[yY][eE][sS])
                for bname in "${imported_bundles[@]}"; do
                    local bundle_name="${bname%.*}"  # strip extension
                    vokun::core::info "Installing bundle: ${bundle_name}"
                    vokun install "$bundle_name" || true
                done
                ;;
            *)
                vokun::core::log "Skipped. Run 'vokun install <bundle>' to install later."
                ;;
        esac
    fi
}

# Merge imported state into existing state
# Adds new bundles from import; does not overwrite existing bundle entries
vokun::export::_merge_state() {
    local import_state_file="$1"
    local state_file="${VOKUN_CONFIG_DIR}/state.json"

    if ! command -v jq &>/dev/null; then
        vokun::core::warn "jq not available — state not merged."
        return
    fi

    if [[ ! -f "$state_file" ]]; then
        cp "$import_state_file" "$state_file"
        vokun::core::success "Imported state file."
        return
    fi

    # Merge: imported bundles are added; existing bundles take priority
    local tmp
    tmp=$(mktemp)
    vokun::core::show_cmd "jq -s '.[0] * {installed_bundles: (.[1].installed_bundles * .[0].installed_bundles)}' ..."
    if jq -s '
        .[0] as $existing |
        .[1] as $imported |
        $existing * {
            installed_bundles: ($imported.installed_bundles + $existing.installed_bundles),
            unmanaged: (($existing.unmanaged // []) + ($imported.unmanaged // []) | unique)
        }
    ' "$state_file" "$import_state_file" > "$tmp" && mv "$tmp" "$state_file"; then
        vokun::core::success "Merged state file."
    else
        rm -f "$tmp"
        vokun::core::error "Failed to merge state files."
    fi
}
