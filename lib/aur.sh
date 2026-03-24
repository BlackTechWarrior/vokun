#!/usr/bin/env bash
# vokun - AUR integrity checking
# Trust scoring, package info, and PKGBUILD inspection

# --- vokun check ---

# Display AUR package info with trust scoring
# Usage: vokun::aur::check <package>
vokun::aur::check() {
    local pkg="${1:-}"

    if [[ -z "$pkg" ]]; then
        vokun::core::error "Usage: vokun check <package>"
        return 1
    fi

    if ! command -v jq &>/dev/null; then
        vokun::core::error "jq is required for AUR checking"
        vokun::core::log "Install it with: sudo pacman -S jq"
        return 1
    fi

    vokun::core::info "Fetching AUR info for '$pkg'..."

    local response
    response=$(curl -s "https://aur.archlinux.org/rpc/v5/info?arg[]=${pkg}")

    local result_count
    result_count=$(printf '%s' "$response" | jq '.resultcount')

    if [[ "$result_count" -eq 0 ]]; then
        vokun::core::error "Package '$pkg' not found in AUR"
        return 1
    fi

    # Parse fields
    local name version maintainer votes popularity
    local last_modified first_submitted description out_of_date

    name=$(printf '%s' "$response" | jq -r '.results[0].Name')
    version=$(printf '%s' "$response" | jq -r '.results[0].Version')
    description=$(printf '%s' "$response" | jq -r '.results[0].Description // "No description"')
    maintainer=$(printf '%s' "$response" | jq -r '.results[0].Maintainer // "orphaned"')
    votes=$(printf '%s' "$response" | jq -r '.results[0].NumVotes')
    popularity=$(printf '%s' "$response" | jq -r '.results[0].Popularity')
    last_modified=$(printf '%s' "$response" | jq -r '.results[0].LastModified')
    first_submitted=$(printf '%s' "$response" | jq -r '.results[0].FirstSubmitted')
    out_of_date=$(printf '%s' "$response" | jq -r '.results[0].OutOfDate // "null"')

    # Convert timestamps to human-readable dates
    local last_updated_str first_submitted_str
    last_updated_str=$(date -d "@${last_modified}" "+%Y-%m-%d" 2>/dev/null || date -r "${last_modified}" "+%Y-%m-%d" 2>/dev/null || echo "unknown")
    first_submitted_str=$(date -d "@${first_submitted}" "+%Y-%m-%d" 2>/dev/null || date -r "${first_submitted}" "+%Y-%m-%d" 2>/dev/null || echo "unknown")

    # Calculate age in days since last update
    local now_epoch age_days
    now_epoch=$(date +%s)
    age_days=$(( (now_epoch - last_modified) / 86400 ))

    # Determine trust level
    local trust_color trust_label
    local is_orphaned=false
    [[ "$maintainer" == "orphaned" || "$maintainer" == "null" ]] && is_orphaned=true

    if [[ "$is_orphaned" == true ]] || (( votes < 10 )) || (( age_days > 365 )); then
        trust_color="$VOKUN_COLOR_RED"
        trust_label="LOW TRUST"
    elif (( votes < 100 )) || (( age_days > 180 )); then
        trust_color="$VOKUN_COLOR_YELLOW"
        trust_label="MODERATE TRUST"
    else
        trust_color="$VOKUN_COLOR_GREEN"
        trust_label="HIGH TRUST"
    fi

    # Display
    printf '\n'
    printf '%s%s%s %s%s%s\n' "$VOKUN_COLOR_BOLD" "$name" "$VOKUN_COLOR_RESET" \
        "$VOKUN_COLOR_DIM" "$version" "$VOKUN_COLOR_RESET"
    printf '%s\n' "$description"
    printf '%s\n' "$(printf '%.0s─' {1..50})"

    printf '  %sMaintainer:%s   %s\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET" "$maintainer"
    printf '  %sVotes:%s        %s\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET" "$votes"
    printf '  %sPopularity:%s   %s\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET" "$popularity"
    printf '  %sLast Updated:%s %s (%d days ago)\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET" "$last_updated_str" "$age_days"
    printf '  %sFirst Submit:%s %s\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET" "$first_submitted_str"

    if [[ "$out_of_date" != "null" ]]; then
        local ood_str
        ood_str=$(date -d "@${out_of_date}" "+%Y-%m-%d" 2>/dev/null || date -r "${out_of_date}" "+%Y-%m-%d" 2>/dev/null || echo "yes")
        printf '  %s%sOut of Date:%s  flagged %s%s\n' "$VOKUN_COLOR_YELLOW" "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET" "$ood_str" "$VOKUN_COLOR_RESET"
    fi

    printf '\n'
    printf '  %s[ %s ]%s\n' "$trust_color" "$trust_label" "$VOKUN_COLOR_RESET"
    printf '\n'
}

# --- vokun diff ---

# Show PKGBUILD for an AUR package
# Usage: vokun::aur::diff <package>
vokun::aur::diff() {
    local pkg="${1:-}"

    if [[ -z "$pkg" ]]; then
        vokun::core::error "Usage: vokun diff <package>"
        return 1
    fi

    # Try AUR helper's built-in diff first
    local aur_helper
    aur_helper=$(vokun::core::get_aur_helper)

    if [[ -n "$aur_helper" ]]; then
        case "$aur_helper" in
            paru)
                vokun::core::show_cmd "$aur_helper -Gp $pkg"
                "$aur_helper" -Gp "$pkg"
                return $?
                ;;
            yay)
                vokun::core::show_cmd "$aur_helper -Gp $pkg"
                "$aur_helper" -Gp "$pkg"
                return $?
                ;;
        esac
    fi

    # Fallback: fetch PKGBUILD from AUR git
    vokun::core::info "Fetching PKGBUILD for '$pkg' from AUR..."

    local url="https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h=${pkg}"
    local pkgbuild

    pkgbuild=$(curl -sf "$url") || {
        vokun::core::error "Could not fetch PKGBUILD for '$pkg'"
        vokun::core::log "Package may not exist in AUR."
        return 1
    }

    # Display with syntax highlighting if bat is available
    if command -v bat &>/dev/null; then
        printf '%s\n' "$pkgbuild" | bat --language=bash --style=plain --paging=never
    else
        printf '%s\n' "$pkgbuild"
    fi
}
