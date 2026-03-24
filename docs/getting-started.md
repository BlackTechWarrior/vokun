---
layout: default
title: Getting Started
nav_order: 2
---

# Getting Started

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

This clones the repository to a temporary directory, runs `make install` (which
copies files to `/usr/local`), and cleans up.

### From source

```bash
git clone https://github.com/blacktechwarrior/vokun.git
cd vokun
sudo make install
```

`make install` places the following files:

| File | Destination |
|------|-------------|
| `vokun` | `/usr/local/bin/vokun` |
| `lib/*.sh` | `/usr/local/share/vokun/lib/` |
| `bundles/*.toml` | `/usr/local/share/vokun/bundles/` |
| `completions/vokun.bash` | `/usr/local/share/bash-completion/completions/vokun` |
| `completions/vokun.fish` | `/usr/local/share/fish/vendor_completions.d/vokun.fish` |

To uninstall: `sudo make uninstall`.

---

## Dependencies

**Required:** Bash 4+ and pacman.

**Optional:**

| Package | Purpose |
|---------|---------|
| `paru` or `yay` | AUR package support |
| `fzf` | Interactive fuzzy pickers |
| `jq` | JSON state tracking |
| `pacman-contrib` | Cache management (`paccache`) |

Vokun works without any of the optional packages. Features that need them
degrade gracefully with a warning.

---

## First commands

### Browse bundles

```bash
vokun list
```

This shows all available bundles grouped by their primary tag (dev, admin, net,
etc.), with installed bundles highlighted.

### Inspect a bundle before installing

```bash
vokun info sysadmin
```

Shows the bundle description, tags, every package with its description, and
whether each package is already installed on your system.

### Install a bundle

```bash
vokun install sysadmin
```

Vokun lists the packages to install, highlights any AUR packages, offers
optional packages separately, shows a total count, and asks for confirmation.
Pass `--yes` or `-y` to skip the prompt.

### Search for bundles

```bash
vokun search python
```

Searches bundle names, descriptions, tags, and package lists.

---

## Configuration

On first run, vokun creates `~/.config/vokun/` with a default state file. To
customize behavior, create `~/.config/vokun/vokun.conf`:

```toml
[general]
aur_helper = "paru"
color = true
confirm = true
fzf = true
```

See the [Configuration](configuration) page for all available options.
