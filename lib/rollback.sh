#!/usr/bin/env bash
# shellcheck disable=SC2034
# vokun - Rollback support
# Undo the last bundle install or remove using the action log

vokun::rollback::run() {
    if [[ -z "$VOKUN_LOG_FILE" || ! -f "$VOKUN_LOG_FILE" ]]; then
        vokun::core::error "No action log found. Nothing to roll back."
        return 1
    fi

    # Find the last reversible action
    local last_entry
    last_entry=$(grep -E '\|bundle-install\||\|bundle-remove\||\|get\||\|yeet\|' "$VOKUN_LOG_FILE" | tail -1)

    if [[ -z "$last_entry" ]]; then
        vokun::core::error "No reversible actions found in the log."
        return 1
    fi

    local timestamp action target details profile
    IFS='|' read -r timestamp action target details profile <<< "$last_entry"

    printf '\n%sRollback%s\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET"
    printf '%s\n\n' "$(printf '%.0s─' {1..50})"

    case "$action" in
        bundle-install)
            printf '  %sLast action:%s Installed bundle %s%s%s\n' \
                "$VOKUN_COLOR_DIM" "$VOKUN_COLOR_RESET" \
                "$VOKUN_COLOR_BOLD" "$target" "$VOKUN_COLOR_RESET"
            printf '  %sAt:%s          %s\n' "$VOKUN_COLOR_DIM" "$VOKUN_COLOR_RESET" "$timestamp"

            if [[ -n "$details" ]]; then
                printf '  %sPackages:%s     %s\n' "$VOKUN_COLOR_DIM" "$VOKUN_COLOR_RESET" "$details"
            fi

            printf '\n  %sRollback will:%s Remove the bundle and its unique packages.\n\n' \
                "$VOKUN_COLOR_YELLOW" "$VOKUN_COLOR_RESET"

            if ! vokun::core::confirm "Undo this install?"; then
                vokun::core::log "Rollback cancelled."
                return 0
            fi

            # Use the bundle remove function
            vokun::bundles::remove "$target"
            vokun::core::log_action "rollback" "$target" "undid bundle-install"
            ;;

        bundle-remove)
            printf '  %sLast action:%s Removed bundle %s%s%s\n' \
                "$VOKUN_COLOR_DIM" "$VOKUN_COLOR_RESET" \
                "$VOKUN_COLOR_BOLD" "$target" "$VOKUN_COLOR_RESET"
            printf '  %sAt:%s          %s\n' "$VOKUN_COLOR_DIM" "$VOKUN_COLOR_RESET" "$timestamp"

            if [[ -n "$details" ]]; then
                printf '  %sPackages:%s     %s\n' "$VOKUN_COLOR_DIM" "$VOKUN_COLOR_RESET" "$details"
            fi

            printf '\n  %sRollback will:%s Reinstall the bundle.\n\n' \
                "$VOKUN_COLOR_YELLOW" "$VOKUN_COLOR_RESET"

            if ! vokun::core::confirm "Undo this removal?"; then
                vokun::core::log "Rollback cancelled."
                return 0
            fi

            # Reinstall the bundle
            vokun::bundles::install "$target"
            vokun::core::log_action "rollback" "$target" "undid bundle-remove"
            ;;

        get)
            printf '  %sLast action:%s Installed package(s) %s%s%s\n' \
                "$VOKUN_COLOR_DIM" "$VOKUN_COLOR_RESET" \
                "$VOKUN_COLOR_BOLD" "$target" "$VOKUN_COLOR_RESET"
            printf '  %sAt:%s          %s\n' "$VOKUN_COLOR_DIM" "$VOKUN_COLOR_RESET" "$timestamp"

            printf '\n  %sRollback will:%s Remove the package(s) with pacman -Rns.\n\n' \
                "$VOKUN_COLOR_YELLOW" "$VOKUN_COLOR_RESET"

            if ! vokun::core::confirm "Undo this install?"; then
                vokun::core::log "Rollback cancelled."
                return 0
            fi

            # shellcheck disable=SC2086
            vokun::core::run_pacman_only "-Rns" $target
            vokun::core::log_action "rollback" "$target" "undid get"
            ;;

        yeet)
            printf '  %sLast action:%s Removed package(s) %s%s%s\n' \
                "$VOKUN_COLOR_DIM" "$VOKUN_COLOR_RESET" \
                "$VOKUN_COLOR_BOLD" "$target" "$VOKUN_COLOR_RESET"
            printf '  %sAt:%s          %s\n' "$VOKUN_COLOR_DIM" "$VOKUN_COLOR_RESET" "$timestamp"

            printf '\n  %sRollback will:%s Reinstall the package(s).\n\n' \
                "$VOKUN_COLOR_YELLOW" "$VOKUN_COLOR_RESET"

            if ! vokun::core::confirm "Undo this removal?"; then
                vokun::core::log "Rollback cancelled."
                return 0
            fi

            # shellcheck disable=SC2086
            vokun::core::run_pacman "-S" "--needed" $target
            vokun::core::log_action "rollback" "$target" "undid yeet"
            ;;

        *)
            vokun::core::error "Cannot roll back action: $action"
            return 1
            ;;
    esac
}
