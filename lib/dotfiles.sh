#!/usr/bin/env bash
# shellcheck disable=SC2034
# vokun - Dotfile management wrapper
# Wraps chezmoi, yadm, stow, or git bare repo behind a unified interface
# Safety first: always confirm before applying changes

VOKUN_DOTFILE_BACKEND=""

# --- Backend detection ---

vokun::dotfiles::detect_backend() {
    if command -v chezmoi &>/dev/null; then
        printf 'chezmoi'
    elif command -v yadm &>/dev/null; then
        printf 'yadm'
    elif command -v stow &>/dev/null; then
        printf 'stow'
    else
        printf ''
    fi
}

vokun::dotfiles::get_backend() {
    # Check config first
    if [[ -f "${VOKUN_CONFIG_DIR}/vokun.conf" ]]; then
        vokun::toml::parse "${VOKUN_CONFIG_DIR}/vokun.conf"
        local configured
        configured=$(vokun::toml::get "dotfiles.backend" "")
        if [[ -n "$configured" ]]; then
            printf '%s' "$configured"
            return
        fi
    fi
    vokun::dotfiles::detect_backend
}

# --- Dispatch ---

vokun::dotfiles::dispatch() {
    local subcmd="${1:-}"
    shift 2>/dev/null || true

    VOKUN_DOTFILE_BACKEND=$(vokun::dotfiles::get_backend)

    case "$subcmd" in
        init)   vokun::dotfiles::init "$@" ;;
        apply)  vokun::dotfiles::apply "$@" ;;
        push)   vokun::dotfiles::push "$@" ;;
        pull)   vokun::dotfiles::pull "$@" ;;
        status) vokun::dotfiles::status ;;
        edit)   vokun::dotfiles::edit "$@" ;;
        "")     vokun::dotfiles::status ;;
        *)
            vokun::core::error "Unknown dotfiles subcommand: $subcmd"
            vokun::core::log ""
            vokun::core::log "Subcommands:"
            vokun::core::log "  init <repo>          Initialize dotfile management"
            vokun::core::log "  apply                Apply dotfiles to the system"
            vokun::core::log "  push                 Push dotfile changes to remote"
            vokun::core::log "  pull                 Pull latest dotfiles from remote"
            vokun::core::log "  status               Show dotfile status"
            vokun::core::log "  edit <file>           Edit a managed dotfile"
            return 1
            ;;
    esac
}

# --- vokun dotfiles init ---

vokun::dotfiles::init() {
    local repo="${1:-}"

    if [[ -n "$VOKUN_DOTFILE_BACKEND" ]]; then
        vokun::core::info "Detected dotfile backend: $VOKUN_DOTFILE_BACKEND"
    else
        vokun::core::warn "No dotfile manager found."
        printf '\n  Supported tools:\n'
        printf '    %schezmoi%s  — %s\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET" "paru -S chezmoi"
        printf '    %syadm%s     — %s\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET" "paru -S yadm"
        printf '    %sstow%s     — %s\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET" "sudo pacman -S stow"
        printf '\n  Install one, then run: vokun dotfiles init [repo-url]\n\n'
        return 1
    fi

    case "$VOKUN_DOTFILE_BACKEND" in
        chezmoi)
            if [[ -n "$repo" ]]; then
                vokun::core::show_cmd "chezmoi init $repo"
                vokun::core::info "This will clone your dotfile repo. No files will be changed yet."
                if vokun::core::confirm "Initialize chezmoi with $repo?"; then
                    chezmoi init "$repo"
                    vokun::core::success "Initialized. Run 'vokun dotfiles apply' to apply configs."
                fi
            else
                vokun::core::show_cmd "chezmoi init"
                chezmoi init
                vokun::core::success "Initialized empty chezmoi config."
            fi
            ;;
        yadm)
            if [[ -n "$repo" ]]; then
                vokun::core::show_cmd "yadm clone $repo"
                vokun::core::info "This will clone your dotfile repo."
                if vokun::core::confirm "Clone dotfiles from $repo?"; then
                    yadm clone "$repo"
                    vokun::core::success "Cloned. Your dotfiles are now managed by yadm."
                fi
            else
                vokun::core::show_cmd "yadm init"
                yadm init
                vokun::core::success "Initialized empty yadm repo."
            fi
            ;;
        stow)
            if [[ -n "$repo" ]]; then
                local stow_dir="${HOME}/.dotfiles"
                vokun::core::show_cmd "git clone $repo $stow_dir"
                vokun::core::info "This will clone your dotfile repo to $stow_dir."
                if vokun::core::confirm "Clone dotfiles from $repo?"; then
                    git clone "$repo" "$stow_dir"
                    vokun::core::success "Cloned to $stow_dir. Run 'vokun dotfiles apply' to symlink configs."
                fi
            else
                local stow_dir="${HOME}/.dotfiles"
                mkdir -p "$stow_dir"
                vokun::core::success "Created $stow_dir. Add your config directories there."
            fi
            ;;
    esac
}

# --- vokun dotfiles apply ---

vokun::dotfiles::apply() {
    if [[ -z "$VOKUN_DOTFILE_BACKEND" ]]; then
        vokun::core::error "No dotfile backend found. Run 'vokun dotfiles init' first."
        return 1
    fi

    printf '\n%sApply Dotfiles%s\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET"
    printf '%s\n\n' "$(printf '%.0s─' {1..50})"

    case "$VOKUN_DOTFILE_BACKEND" in
        chezmoi)
            # Show diff first (safety)
            vokun::core::info "Preview of changes:"
            vokun::core::show_cmd "chezmoi diff"
            local diff_output
            diff_output=$(chezmoi diff 2>/dev/null || true)
            if [[ -z "$diff_output" ]]; then
                vokun::core::success "No changes to apply. Everything is in sync."
                return 0
            fi
            printf '%s\n' "$diff_output"
            printf '\n'
            if vokun::core::confirm "Apply these changes?"; then
                vokun::core::show_cmd "chezmoi apply"
                chezmoi apply
                vokun::core::log_action "dotfiles-apply" "chezmoi" ""
                vokun::core::success "Dotfiles applied."
            fi
            ;;
        yadm)
            vokun::core::info "Preview of changes:"
            vokun::core::show_cmd "yadm diff"
            local diff_output
            diff_output=$(yadm diff 2>/dev/null || true)
            if [[ -z "$diff_output" ]]; then
                vokun::core::success "No changes to apply. Everything is in sync."
                return 0
            fi
            printf '%s\n' "$diff_output"
            printf '\n'
            vokun::core::info "yadm applies dotfiles on clone. Use 'yadm checkout' to restore files."
            if vokun::core::confirm "Run yadm checkout?"; then
                vokun::core::show_cmd "yadm checkout ~"
                yadm checkout ~
                vokun::core::log_action "dotfiles-apply" "yadm" ""
                vokun::core::success "Dotfiles applied."
            fi
            ;;
        stow)
            local stow_dir="${HOME}/.dotfiles"
            if [[ ! -d "$stow_dir" ]]; then
                vokun::core::error "Dotfiles directory not found: $stow_dir"
                return 1
            fi
            vokun::core::info "Will symlink configs from $stow_dir to ~"
            printf '\n  Available packages:\n'
            local -a stow_pkgs=()
            local d
            for d in "$stow_dir"/*/; do
                [[ -d "$d" ]] || continue
                local pkg_name
                pkg_name=$(basename "$d")
                stow_pkgs+=("$pkg_name")
                printf '    %s\n' "$pkg_name"
            done
            if [[ ${#stow_pkgs[@]} -eq 0 ]]; then
                vokun::core::warn "No packages found in $stow_dir"
                return 0
            fi
            printf '\n'
            if vokun::core::confirm "Symlink all packages?"; then
                for pkg_name in "${stow_pkgs[@]}"; do
                    vokun::core::show_cmd "stow -d $stow_dir -t ~ $pkg_name"
                    stow -d "$stow_dir" -t ~ "$pkg_name"
                done
                vokun::core::log_action "dotfiles-apply" "stow" "${stow_pkgs[*]}"
                vokun::core::success "Dotfiles symlinked."
            fi
            ;;
    esac
}

# --- vokun dotfiles push ---

vokun::dotfiles::push() {
    if [[ -z "$VOKUN_DOTFILE_BACKEND" ]]; then
        vokun::core::error "No dotfile backend found."
        return 1
    fi

    case "$VOKUN_DOTFILE_BACKEND" in
        chezmoi)
            vokun::core::show_cmd "chezmoi git -- add -A && chezmoi git -- commit && chezmoi git -- push"
            vokun::core::info "Committing and pushing chezmoi changes..."
            chezmoi git -- add -A
            chezmoi git -- commit -m "Update dotfiles via vokun"
            chezmoi git -- push
            vokun::core::log_action "dotfiles-push" "chezmoi" ""
            vokun::core::success "Pushed."
            ;;
        yadm)
            vokun::core::show_cmd "yadm add -u && yadm commit && yadm push"
            vokun::core::info "Committing and pushing yadm changes..."
            yadm add -u
            yadm commit -m "Update dotfiles via vokun"
            yadm push
            vokun::core::log_action "dotfiles-push" "yadm" ""
            vokun::core::success "Pushed."
            ;;
        stow)
            local stow_dir="${HOME}/.dotfiles"
            if [[ ! -d "${stow_dir}/.git" ]]; then
                vokun::core::error "$stow_dir is not a git repo. Initialize with 'git init' first."
                return 1
            fi
            vokun::core::show_cmd "cd $stow_dir && git add -A && git commit && git push"
            (cd "$stow_dir" && git add -A && git commit -m "Update dotfiles via vokun" && git push)
            vokun::core::log_action "dotfiles-push" "stow" ""
            vokun::core::success "Pushed."
            ;;
    esac
}

# --- vokun dotfiles pull ---

vokun::dotfiles::pull() {
    if [[ -z "$VOKUN_DOTFILE_BACKEND" ]]; then
        vokun::core::error "No dotfile backend found."
        return 1
    fi

    case "$VOKUN_DOTFILE_BACKEND" in
        chezmoi)
            vokun::core::show_cmd "chezmoi update"
            vokun::core::info "Pulling latest dotfiles..."
            chezmoi update
            vokun::core::log_action "dotfiles-pull" "chezmoi" ""
            vokun::core::success "Updated."
            ;;
        yadm)
            vokun::core::show_cmd "yadm pull"
            yadm pull
            vokun::core::log_action "dotfiles-pull" "yadm" ""
            vokun::core::success "Updated."
            ;;
        stow)
            local stow_dir="${HOME}/.dotfiles"
            vokun::core::show_cmd "cd $stow_dir && git pull"
            (cd "$stow_dir" && git pull)
            vokun::core::info "Pulled. Run 'vokun dotfiles apply' to update symlinks."
            vokun::core::log_action "dotfiles-pull" "stow" ""
            ;;
    esac
}

# --- vokun dotfiles status ---

vokun::dotfiles::status() {
    printf '\n%sDotfile Status%s\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET"
    printf '%s\n\n' "$(printf '%.0s─' {1..50})"

    if [[ -z "$VOKUN_DOTFILE_BACKEND" ]]; then
        printf '  %sBackend:%s   not configured\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET"
        printf '\n  Run %svokun dotfiles init%s to set up dotfile management.\n\n' \
            "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET"
        return 0
    fi

    printf '  %sBackend:%s   %s%s%s\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET" \
        "$VOKUN_COLOR_GREEN" "$VOKUN_DOTFILE_BACKEND" "$VOKUN_COLOR_RESET"

    case "$VOKUN_DOTFILE_BACKEND" in
        chezmoi)
            local managed_count
            managed_count=$(chezmoi managed 2>/dev/null | wc -l || echo "0")
            printf '  %sManaged:%s   %s files\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET" "$managed_count"
            local source_dir
            source_dir=$(chezmoi source-path 2>/dev/null || echo "unknown")
            printf '  %sSource:%s    %s\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET" "$source_dir"
            ;;
        yadm)
            local tracked_count
            tracked_count=$(yadm list 2>/dev/null | wc -l || echo "0")
            printf '  %sTracked:%s   %s files\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET" "$tracked_count"
            local yadm_repo
            yadm_repo=$(yadm introspect repo 2>/dev/null || echo "~/.local/share/yadm/repo.git")
            printf '  %sRepo:%s      %s\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET" "$yadm_repo"
            ;;
        stow)
            local stow_dir="${HOME}/.dotfiles"
            printf '  %sDirectory:%s %s\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET" "$stow_dir"
            if [[ -d "$stow_dir" ]]; then
                local pkg_count=0
                local d
                for d in "$stow_dir"/*/; do
                    [[ -d "$d" ]] && ((pkg_count++))
                done
                printf '  %sPackages:%s  %d\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET" "$pkg_count"
            else
                printf '  %sStatus:%s    not initialized\n' "$VOKUN_COLOR_BOLD" "$VOKUN_COLOR_RESET"
            fi
            ;;
    esac
    printf '\n'
}

# --- vokun dotfiles edit ---

vokun::dotfiles::edit() {
    local file="${1:-}"

    if [[ -z "$file" ]]; then
        vokun::core::error "Usage: vokun dotfiles edit <file>"
        return 1
    fi

    if [[ -z "$VOKUN_DOTFILE_BACKEND" ]]; then
        vokun::core::error "No dotfile backend found."
        return 1
    fi

    case "$VOKUN_DOTFILE_BACKEND" in
        chezmoi)
            vokun::core::show_cmd "chezmoi edit $file"
            chezmoi edit "$file"
            ;;
        yadm|stow)
            local editor="${EDITOR:-nano}"
            vokun::core::show_cmd "$editor $file"
            "$editor" "$file"
            ;;
    esac
}
