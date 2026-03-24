---
layout: default
title: Configuration
nav_order: 5
---

# Configuration

Vokun reads its configuration from `~/.config/vokun/vokun.conf`. This file uses
TOML syntax and is entirely optional -- vokun works with sensible defaults when
no config file exists.

---

## Full reference

```toml
[general]
aur_helper = "paru"           # Which AUR helper to use: "paru", "yay", or ""
color = true                   # Enable colored terminal output
confirm = true                 # Prompt for confirmation before installs/removals
fzf = true                     # Use fzf for interactive selection when available

[sync]
hook = false                   # Install a pacman hook that notifies on new packages
auto_prompt = true             # After 'vokun get', prompt to add the package to a bundle

[dotfiles]
backend = ""                   # Dotfile manager: "chezmoi", "yadm", "stow", or "" (auto-detect)

[aur]
trust_threshold = 50           # Minimum AUR votes to consider a package "trusted"
warn_age_days = 180            # Warn if an AUR package has not been updated in this many days
show_pkgbuild = false          # Automatically display the PKGBUILD on AUR installs
```

---

## Options

### `[general]`

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `aur_helper` | string | auto-detected | AUR helper command. Set to `"paru"`, `"yay"`, or `""` to disable AUR support. When unset, vokun auto-detects paru first, then yay. |
| `color` | boolean | `true` | Whether to use ANSI colors in output. Also respects the `NO_COLOR` environment variable and the `--no-color` flag. |
| `confirm` | boolean | `true` | Whether to ask for confirmation before modifying the system. The `--yes` / `-y` flag overrides this per-invocation. |
| `fzf` | boolean | `true` | Whether to use `fzf` for interactive pickers. When `false` or when fzf is not installed, vokun falls back to numbered menus. |

### `[sync]`

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `hook` | boolean | `false` | When `true`, installs a pacman hook that prints a reminder to run `vokun sync` after packages are installed outside of vokun. You can also manage this manually with `vokun hook install` and `vokun hook remove`. |
| `auto_prompt` | boolean | `true` | When `true`, `vokun get` prompts you to add the newly installed package to a bundle. |

### `[dotfiles]`

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `backend` | string | auto-detected | Which dotfile manager to use: `"chezmoi"`, `"yadm"`, `"stow"`, or `""` to auto-detect. When unset, vokun checks for chezmoi first, then yadm, then stow. |

### `[aur]`

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `trust_threshold` | integer | `50` | Minimum number of AUR votes for a package to be considered trusted. Packages below this threshold receive a warning. |
| `warn_age_days` | integer | `180` | Number of days since last update after which an AUR package triggers a staleness warning. |
| `show_pkgbuild` | boolean | `false` | When `true`, the PKGBUILD is displayed automatically before installing an AUR package. |

---

## Profiles

Profiles let you maintain independent sets of installed bundles. This is useful
when the same machine serves different roles (e.g. work vs. personal) or when
you want to test bundle changes without affecting your main state.

```bash
vokun profile list              # List all profiles
vokun profile show              # Show the active profile name
vokun profile create work       # Create a new profile
vokun profile switch work       # Switch to the "work" profile
vokun profile delete work       # Delete a profile
```

Each profile has its own state file:

| Profile | State file |
|---------|------------|
| `default` | `state.json` |
| `work` | `state-work.json` |
| `<name>` | `state-<name>.json` |

The active profile is tracked in `~/.config/vokun/.active_profile`. The default
profile uses `state.json` (no suffix) for backwards compatibility -- if
`.active_profile` does not exist, vokun uses the default profile.

---

## File locations

| Path | Purpose |
|------|---------|
| `~/.config/vokun/vokun.conf` | User configuration (TOML) |
| `~/.config/vokun/state.json` | Bundle install state for the default profile |
| `~/.config/vokun/state-<name>.json` | Bundle install state for named profiles |
| `~/.config/vokun/.active_profile` | Tracks the currently active profile |
| `~/.config/vokun/bundles/custom/` | User-created bundle definitions |
| `~/.config/vokun/vokun.log` | Action log (installs, removals, rollbacks, dotfiles actions) |

The config directory follows the XDG Base Directory specification. If
`XDG_CONFIG_HOME` is set, vokun uses `$XDG_CONFIG_HOME/vokun/` instead of
`~/.config/vokun/`.

---

## Environment variables

| Variable | Description |
|----------|-------------|
| `NO_COLOR` | When set (to any value), disables all colored output. See [no-color.org](https://no-color.org/). |
| `XDG_CONFIG_HOME` | Overrides the default config directory (`~/.config`). |

---

## Command-line flags

These flags override config file settings for a single invocation:

| Flag | Overrides |
|------|-----------|
| `--yes`, `-y` | `general.confirm = false` |
| `--no-color` | `general.color = false` |
