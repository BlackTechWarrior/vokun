#!/usr/bin/env bash
# shellcheck disable=SC2034
# vokun - Pacman hook management
# Install/remove libalpm hook for automatic sync notifications

VOKUN_HOOK_PATH="/usr/share/libalpm/hooks/vokun-notify.hook"

# --- vokun hook ---
vokun::hook::dispatch() {
    local action="${1:-}"
    shift 2>/dev/null || true

    case "$action" in
        install) vokun::hook::install "$@" ;;
        remove)  vokun::hook::remove "$@" ;;
        *)
            vokun::core::error "Usage: vokun hook <install|remove>"
            return 1
            ;;
    esac
}

# --- vokun hook install ---
vokun::hook::install() {
    if [[ -f "$VOKUN_HOOK_PATH" ]]; then
        vokun::core::warn "Hook already installed at $VOKUN_HOOK_PATH"
        return 0
    fi

    vokun::core::info "Installing pacman hook for vokun sync notifications"
    printf '\n'
    printf '  %sFile:%s  %s\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET" "$VOKUN_HOOK_PATH"
    printf '  %sExec:%s  /usr/local/bin/vokun sync --auto --quiet\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET"
    printf '  %sWhen:%s  After every package install\n\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET"

    if ! vokun::core::confirm "Install hook?"; then
        vokun::core::log "Aborted."
        return 1
    fi

    local tmpfile
    tmpfile=$(mktemp)

    cat > "$tmpfile" <<'HOOKEOF'
[Trigger]
Operation = Install
Type = Package
Target = *

[Action]
Description = Vokun: checking for untracked packages...
When = PostTransaction
Exec = /usr/local/bin/vokun sync --auto --quiet
HOOKEOF

    vokun::core::show_cmd "sudo mv $tmpfile $VOKUN_HOOK_PATH"
    if sudo mv "$tmpfile" "$VOKUN_HOOK_PATH"; then
        sudo chmod 644 "$VOKUN_HOOK_PATH"
        vokun::core::success "Hook installed successfully."
    else
        rm -f "$tmpfile"
        vokun::core::error "Failed to install hook."
        return 1
    fi
}

# --- vokun hook remove ---
vokun::hook::remove() {
    if [[ ! -f "$VOKUN_HOOK_PATH" ]]; then
        vokun::core::warn "Hook not found at $VOKUN_HOOK_PATH"
        return 0
    fi

    vokun::core::info "Removing pacman hook"
    printf '  %s%s%s\n\n' "$VOKUN_COLOR_DIM" "$VOKUN_HOOK_PATH" "$VOKUN_COLOR_RESET"

    if ! vokun::core::confirm "Remove hook?"; then
        vokun::core::log "Aborted."
        return 1
    fi

    vokun::core::show_cmd "sudo rm $VOKUN_HOOK_PATH"
    if sudo rm "$VOKUN_HOOK_PATH"; then
        vokun::core::success "Hook removed successfully."
    else
        vokun::core::error "Failed to remove hook."
        return 1
    fi
}
