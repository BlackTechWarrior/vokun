<h1><img src="docs/vokun-logo.png" alt="vokun" height="32" style="vertical-align: middle;"> Vokun</h1>

**Task-oriented package bundle manager for Arch Linux.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![CI](https://github.com/blacktechwarrior/vokun/actions/workflows/ci.yml/badge.svg)](https://github.com/blacktechwarrior/vokun/actions/workflows/ci.yml)
[![AUR](https://img.shields.io/aur/version/vokun)](https://aur.archlinux.org/packages/vokun)

---

## What is Vokun?

Vokun is a pure Bash CLI tool that wraps `pacman`, `paru`, and `yay` to provide
task-oriented package bundles for Arch Linux and pacman-based distributions such
as CachyOS, EndeavourOS, and Manjaro. Instead of memorizing dozens of individual
package names, you install a **bundle** -- a curated group of packages organized
around a task like "python development" or "system administration" -- with a
single command.

Under the hood, vokun is a thin wrapper. Every operation shows you the exact
`pacman` or `paru` command being run, so nothing is hidden. Packages installed
through vokun are standard system packages; there is no lock-in and no custom
package format. You can mix `vokun install` with plain `pacman -S` freely, and
use `vokun sync` later to reconcile the two.

The name "vokun" means "shadow" in the dragon language from The Elder Scrolls V:
Skyrim. It has zero namespace collisions in the CLI/package tool space.

---

## Quick Start

```bash
paru -S vokun            # Install from the AUR
vokun setup              # Check dependencies, bootstrap paru if needed
vokun                    # Launch interactive mode (first-run wizard on fresh install)
vokun list               # Browse available bundles
vokun install sysadmin   # Install the sysadmin toolkit
```

---

## Installation

### AUR (recommended)

```bash
paru -S vokun
# or
yay -S vokun
```

### One-liner

```bash
curl -fsSL https://raw.githubusercontent.com/blacktechwarrior/vokun/main/install.sh | bash
```

### From source

```bash
git clone https://github.com/blacktechwarrior/vokun.git
cd vokun
sudo make install
```

---

## Usage

### Bundle commands

```bash
vokun install <bundle>                      # Install a bundle (shows packages, confirms)
vokun install <bundle> --pick               # Interactively select which packages to install
vokun install <bundle> --exclude pkg1,pkg2  # Install everything except these packages
vokun install <bundle> --only pkg1,pkg2     # Install only these packages from the bundle
vokun install <bundle> --dry-run            # Preview what would be installed
vokun rollback                              # Undo the last reversible action
vokun remove  <bundle>                      # Remove packages unique to this bundle
vokun remove  <bundle> --dry-run            # Preview what would be removed
vokun select  <bundle>                      # Change pick-one selections for a bundle
vokun list                                  # List all available bundles
vokun list --installed                      # List installed bundles only
vokun info    <bundle>                      # Show bundle contents without installing
vokun search  <keyword>                     # Search bundles by name, tag, or package
```

Install also runs a **conflict pre-flight check** -- before calling pacman, each
package is checked via `pacman -Si` for conflicts with already-installed
packages. If conflicts are found, you are warned before proceeding.

### Package commands (pacman/paru aliases)

```bash
vokun get     <pkg>             # Install a package          (pacman -S)
vokun yeet    <pkg>             # Remove with deps/configs   (pacman -Rns)
vokun find    <query>           # Search repos               (pacman -Ss)
vokun find    <query> --aur     # Search repos + AUR
vokun which   <pkg>             # Info on installed package   (pacman -Qi)
vokun owns    <file>            # Which package owns a file   (pacman -Qo)
vokun update                    # Full system update          (pacman -Syu)
vokun update  --aur             # Include AUR packages
vokun update  --check           # Show available upgrades     (checkupdates)
vokun update  --check --aur     # Include AUR in check        (paru -Qu)
```

### Action log

```bash
vokun log                                   # Show last 20 logged actions
vokun log --count 50                        # Show last 50 logged actions
```

Every bundle install, remove, get, yeet, rollback, and dotfiles action is
recorded in `~/.config/vokun/vokun.log`. Entries are color-coded by action type
(green for installs, red for removals).

### Dotfile management

```bash
vokun dotfiles init                         # Initialize dotfile tracking
vokun dotfiles apply                        # Apply dotfiles to the system
vokun dotfiles push                         # Push dotfile changes upstream
vokun dotfiles pull                         # Pull dotfile changes from upstream
vokun dotfiles status                       # Show dotfile tracking status
vokun dotfiles edit                         # Edit a tracked dotfile
```

Wraps chezmoi, yadm, or stow behind a unified interface. The backend is
auto-detected or can be set via `dotfiles.backend` in `vokun.conf`. All
destructive actions show a preview and require confirmation.

### Query & diagnostics

```bash
vokun status                    # Show system overview (profile, bundles, packages, times)
vokun why <pkg>                 # Show which bundles include a package
vokun untracked                 # List ad-hoc installs not in any bundle
vokun doctor                    # Run all health checks (deps, drift, orphans, cache)
vokun snapshot create <name>    # Save current system state
vokun snapshot list             # List saved snapshots
vokun snapshot diff <name>      # Compare snapshot vs current state
vokun snapshot restore <name>   # Restore to a snapshot (--dry-run to preview)
vokun snapshot delete <name>    # Remove a snapshot
```

### System maintenance

```bash
vokun orphans                   # List orphaned packages
vokun orphans --clean           # Remove orphans
vokun cache                     # Show cache size and stats
vokun cache   --clean           # Keep last 2 versions (paccache -rk2)
vokun cache   --purge           # Remove all cached packages
vokun size                      # List packages sorted by installed size
vokun recent                    # Show recently installed packages
vokun foreign                   # List AUR/foreign packages
vokun explicit                  # List explicitly installed packages
vokun broken                    # Check for broken symlinks and deps
```

### Portability

```bash
vokun export                    # Export custom bundles and config (TOML)
vokun export mybackup.toml      # Export to a specific file
vokun export --json             # Export in JSON format
vokun import <file>             # Import bundles from a file
vokun import <file> --dry       # Preview import without applying
```

When importing, vokun shows **hook safety warnings** -- any `post_install`
commands found in the imported bundles are displayed for review before you
confirm the import.

### Sync

```bash
vokun sync                      # Detect untracked packages (forward sync)
vokun sync --auto               # Auto-add untracked packages without prompting
vokun sync --quiet              # Suppress informational output
```

Sync also performs **reverse sync** (detects packages removed outside vokun) and
**drift detection** (compares installed state against current TOML definitions to
find new or removed packages upstream).

### Profiles

```bash
vokun profile show              # Show the active profile
vokun profile list              # List all profiles
vokun profile switch <name>     # Switch to a different profile
vokun profile create <name>     # Create a new profile
vokun profile delete <name>     # Delete a profile
```

Profiles let you maintain separate sets of installed bundles. Each profile has
its own state file (`state-<name>.json`). The default profile uses `state.json`
for backwards compatibility.

### AUR utilities

```bash
vokun check <package>           # AUR trust scoring (votes, age, maintainer)
vokun diff  <package>           # View the PKGBUILD for an AUR package
```

### Automation

```bash
vokun hook install              # Install pacman notification hook
vokun hook install --dry-run    # Preview without changes
vokun hook remove               # Remove the hook
vokun hook remove  --dry-run    # Preview removal
vokun setup                     # Check dependencies and bootstrap paru
vokun uninstall                 # Remove vokun from the system
```

### Example output

```
$ vokun info sysadmin

sysadmin (v1.0.0)
System Administration Toolkit
Tags: admin, essentials, cli
--------------------------------------------------

  Packages:
    htop                      Interactive process viewer
    btop                      Resource monitor with rich TUI
    fastfetch                 Fast system information tool
    fd                        Simple, fast alternative to find
    ripgrep                   Blazingly fast recursive text search
    bat                       Cat clone with syntax highlighting
    eza                       Modern replacement for ls
    fzf                       General-purpose fuzzy finder
    ...

  Optional:
    sd                        Intuitive find-and-replace CLI
    choose                    Human-friendly alternative to cut/awk
```

---

## Default Bundle Catalog

Vokun ships with 24 default bundles across six categories.

### Essentials

| Bundle | Tags | Key Packages |
|--------|------|--------------|
| `coding` | dev, essentials | git, base-devel, cmake, gdb, valgrind, strace, man-db, tldr |
| `sysadmin` | admin, essentials, cli | htop, btop, fastfetch, fd, ripgrep, bat, eza, dust, duf, fzf, zoxide |
| `networking` | net, admin | nmap, wireshark-cli, traceroute, mtr, curl, wget, iperf3, tcpdump, socat |

### Development

| Bundle | Tags | Key Packages |
|--------|------|--------------|
| `python-dev` | dev, python | python, python-pip, ipython, python-virtualenv, ruff, mypy, python-pytest |
| `c-cpp-dev` | dev, c, cpp, systems | gcc, clang, gdb, valgrind, cmake, cppcheck |
| `rust-dev` | dev, rust, systems | rustup, cargo-watch (AUR), cargo-edit (AUR), sccache (AUR) |
| `web-dev` | dev, web, js | nodejs, npm, bun-bin (AUR), deno (AUR) |
| `java-dev` | dev, java | jdk-openjdk, maven, gradle |
| `go-dev` | dev, go | go, gopls (AUR) |

### Specialized

| Bundle | Tags | Key Packages |
|--------|------|--------------|
| `embedded` | dev, embedded, hardware | openocd, minicom, picocom, arm-none-eabi-gcc, arm-none-eabi-gdb |
| `fpga-dev` | dev, fpga, hardware | iverilog, gtkwave, verilator, yosys, nextpnr-ice40 (AUR) |
| `security` | sec, hacking, pentesting | nmap, wireshark-cli, john, hashcat, aircrack-ng, hydra, gobuster |

### Creative and Media

| Bundle | Tags | Key Packages |
|--------|------|--------------|
| `multimedia` | media, creative | ffmpeg, mpv, imagemagick, yt-dlp, sox, gimp, inkscape |
| `latex` | writing, academic | texlive-basic, texlive-latexextra, biber, texlab, pandoc |
| `gaming` | gaming, fun | steam, lutris, wine, gamemode, mangohud, proton-ge-custom-bin (AUR) |

### Infrastructure

| Bundle | Tags | Key Packages |
|--------|------|--------------|
| `vm-container` | devops, infra | docker, podman, qemu-full, virt-manager, vagrant, libvirt |
| `cloud-tools` | devops, cloud | kubectl, helm, terraform, aws-cli-v2 (AUR) |

### Desktop and Productivity

| Bundle | Tags | Key Packages |
|--------|------|--------------|
| `fonts` | desktop, appearance | ttf-fira-code, noto-fonts, noto-fonts-emoji, ttf-jetbrains-mono |
| `terminal-rice` | desktop, rice, terminal | starship, tmux, zsh, neovim, alacritty |

---

## Configuration

Vokun stores its configuration in `~/.config/vokun/vokun.conf` (TOML format):

```toml
[general]
aur_helper = "paru"           # paru, yay, or none (auto-detected if unset)
color = true                   # Colored output
confirm = true                 # Ask before installing (--yes to override)
fzf = true                     # Use fzf for interactive pickers if available

[sync]
hook = false                   # Install pacman hook for new-package notifications
auto_prompt = true             # After 'vokun get', prompt to add to a bundle

[dotfiles]
backend = ""                   # chezmoi, yadm, or stow (auto-detected if unset)

[aur]
trust_threshold = 50           # Minimum votes for "trusted" AUR status
warn_age_days = 180            # Warn if an AUR package has not been updated in this many days
show_pkgbuild = false          # Automatically display PKGBUILD on AUR installs
```

State is tracked in `~/.config/vokun/state.json`. This file records which
bundles are installed, which packages belong to each bundle, and which packages
were skipped. It is managed automatically; you should not need to edit it by
hand.

---

## Creating Custom Bundles

Custom bundles live in `~/.config/vokun/bundles/custom/` and use TOML format.
Create a file such as `my-tools.toml`:

```toml
[meta]
name = "My Favorite Tools"
description = "Personal selection of daily-driver utilities"
tags = ["personal", "cli"]
version = "1.0.0"

[packages]
neovim = "Hyperextensible Vim-based text editor"
tmux = "Terminal multiplexer for managing multiple sessions"
starship = "Cross-shell prompt with smart, minimal defaults"

[packages.aur]
visual-studio-code-bin = "Microsoft VS Code (prebuilt binary)"

[packages.optional]
wezterm = "GPU-accelerated terminal emulator with Lua configuration"

[hooks]
post_install = [
    "echo 'All set! Restart your shell to pick up changes.'"
]
```

**Sections:**

- `[meta]` -- Bundle metadata: name, description, tags (used by `vokun search`), and version. Set `extends = "sysadmin"` to inherit packages from another bundle, or `extends = ["sysadmin", "python-dev"]` for multi-parent inheritance (mixins).
- `[packages]` -- Core packages from the official repositories. Each key is a package name; the value is a human-readable description shown during install.
- `[packages.aur]` -- AUR packages. These are flagged with integrity warnings and require an AUR helper (paru or yay).
- `[packages.optional]` -- Packages offered but not selected by default. The user is asked whether to include them during install.
- `[hooks]` -- Lifecycle hook arrays: `pre_install`, `post_install`, `pre_remove`, `post_remove`. Hook commands are shown to the user and require confirmation before execution.

Once the file is saved, the bundle appears immediately in `vokun list` and can
be installed with `vokun install my-tools`.

You can also manage custom bundles from the command line:

```bash
vokun bundle create <name>      # Create a new custom bundle interactively
vokun bundle add <bundle> <pkg> # Add a package to an existing bundle
vokun bundle rm <bundle> <pkg>  # Remove a package from a bundle
vokun bundle edit <bundle>      # Open a bundle in your editor
vokun bundle delete <bundle>    # Delete a custom bundle
```

**Note:** Colors are automatically disabled when output is piped to another
command or redirected to a file.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on adding bundles, coding
style, testing, and the pull request process.

---

## License

MIT -- see [LICENSE](LICENSE).
