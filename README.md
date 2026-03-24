# Vokun

**Task-oriented package bundle manager for Arch Linux.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![CI](https://github.com/blacktechwarrior/vokun/actions/workflows/ci.yml/badge.svg)](https://github.com/blacktechwarrior/vokun/actions/workflows/ci.yml)

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
git clone https://github.com/blacktechwarrior/vokun.git
cd vokun && sudo make install
vokun                    # Launch interactive mode
vokun list               # Browse available bundles
vokun install sysadmin   # Install the sysadmin toolkit
```

---

## Installation

### From source (recommended)

```bash
git clone https://github.com/blacktechwarrior/vokun.git
cd vokun
sudo make install
```

### One-liner

```bash
curl -fsSL https://raw.githubusercontent.com/blacktechwarrior/vokun/main/install.sh | bash
```

### AUR (coming soon)

AUR package submission is planned. Once available:

```bash
paru -S vokun
# or
yay -S vokun
```

---

## Usage

### Bundle commands

```bash
vokun install <bundle>          # Install a bundle (shows packages, confirms)
vokun install <bundle> --yes    # Skip confirmation
vokun remove  <bundle>          # Remove packages unique to this bundle
vokun list                      # List all available bundles
vokun list --installed          # List installed bundles only
vokun info    <bundle>          # Show bundle contents without installing
vokun search  <keyword>         # Search bundles by name, tag, or package
```

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
vokun export --json             # Export in JSON format
vokun import <file>             # Import bundles from a file
vokun import <file> --dry       # Preview import without applying
```

### Automation

```bash
vokun hook install              # Install pacman notification hook
vokun hook install --dry-run    # Preview without changes
vokun hook remove               # Remove the hook
vokun hook remove  --dry-run    # Preview removal
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

- `[meta]` -- Bundle metadata: name, description, tags (used by `vokun search`), and version.
- `[packages]` -- Core packages from the official repositories. Each key is a package name; the value is a human-readable description shown during install.
- `[packages.aur]` -- AUR packages. These are flagged with integrity warnings and require an AUR helper (paru or yay).
- `[packages.optional]` -- Packages offered but not selected by default. The user is asked whether to include them during install.
- `[hooks]` -- `post_install` is an array of shell commands executed after a successful install.

Once the file is saved, the bundle appears immediately in `vokun list` and can
be installed with `vokun install my-tools`.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on adding bundles, coding
style, testing, and the pull request process.

---

## License

MIT -- see [LICENSE](LICENSE).
