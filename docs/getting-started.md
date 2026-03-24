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
| `completions/_vokun` | `/usr/local/share/zsh/site-functions/_vokun` |
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

## Initial setup

After installing, run the setup command to verify dependencies and optionally
bootstrap an AUR helper:

```bash
vokun setup
```

This checks for required tools (Bash 4+, pacman, jq) and optional ones (paru,
yay, fzf, pacman-contrib), offering to install anything that is missing.

You can also run `vokun doctor` at any time for a comprehensive health check
covering dependencies, sync drift, broken packages, orphans, cache size, and
untracked packages:

```bash
vokun doctor
```

---

## First commands

### Interactive mode

The fastest way to explore vokun is to run it with no arguments:

```bash
vokun
```

This launches an interactive menu (powered by `fzf` when available) where you
can browse bundles, install, remove, and access every command without memorizing
subcommands. On a fresh install (no state file), a first-run wizard guides you
through initial configuration.

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

### Find which bundles include a package

```bash
vokun why strace
```

Shows every bundle that contains a package and whether it is installed. Useful
when deciding whether to add a package to a custom bundle or when investigating
what installed it.

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

---

## Profiles

If you need separate sets of installed bundles (e.g. for work and personal),
use profiles:

```bash
vokun profile create work
vokun profile switch work
vokun install coding           # Installed under the "work" profile only
vokun profile switch default   # Switch back to the default profile
```

See the [Configuration](configuration) page for details on how profiles work.

---

## Dotfile management

Vokun can manage your dotfiles through a unified interface that wraps chezmoi,
yadm, or stow. It auto-detects which backend is installed, or you can set
`dotfiles.backend` in your config. See the [Commands](commands) page for full
details.

```bash
vokun dotfiles init            # Initialize dotfile tracking
vokun dotfiles apply           # Apply dotfiles to the system
vokun dotfiles status          # Check status of tracked dotfiles
```

---

## Rollback

If you make a mistake, `vokun rollback` undoes your last reversible action
(bundle install, bundle remove, get, or yeet). Vokun shows what will be undone
and confirms before proceeding. Every action is recorded in the action log,
which you can review with `vokun log`.
