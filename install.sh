#!/usr/bin/env bash
# vokun installer -- clone and install vokun from source
# Usage: curl -fsSL https://raw.githubusercontent.com/blacktechwarrior/vokun/main/install.sh | bash
set -euo pipefail

REPO="https://github.com/blacktechwarrior/vokun.git"
TMPDIR=""

cleanup() {
    if [[ -n "$TMPDIR" && -d "$TMPDIR" ]]; then
        rm -rf "$TMPDIR"
    fi
}
trap cleanup EXIT

info()  { printf '\033[0;34m::\033[0m \033[1m%s\033[0m\n' "$*"; }
error() { printf '\033[0;31m:: ERROR:\033[0m %s\n' "$*" >&2; }

# --- Preflight checks ---

if ! command -v git &>/dev/null; then
    error "git is required but not installed."
    echo "  Install it with: sudo pacman -S git"
    exit 1
fi

if ! command -v make &>/dev/null; then
    error "make is required but not installed."
    echo "  Install it with: sudo pacman -S base-devel"
    exit 1
fi

# --- Install ---

info "Cloning vokun..."
TMPDIR=$(mktemp -d)
git clone --depth 1 "$REPO" "$TMPDIR/vokun"

info "Installing vokun to /usr/local..."
echo "  This will copy files to /usr/local/bin and /usr/local/share."
echo "  You may be prompted for your password by sudo."
echo ""

cd "$TMPDIR/vokun"
sudo make install

echo ""
info "vokun has been installed successfully."
echo "  Run 'vokun list' to see available bundles."
echo "  Run 'vokun help' for usage information."
