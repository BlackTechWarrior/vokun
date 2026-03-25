---
layout: default
title: Command Reference
nav_order: 3
---

# Command Reference

## Interactive mode

Running `vokun` with no arguments launches an interactive menu powered by `fzf`
(or a numbered fallback menu when fzf is not available). From there you can
browse bundles, install, remove, and access every command without memorizing
subcommands.

On a **fresh install** (no state file present), vokun launches a first-run
wizard that walks you through initial configuration.

```
vokun
```

---

## Global flags

| Flag | Description |
|------|-------------|
| `--yes`, `-y` | Skip confirmation prompts |
| `--no-color` | Disable colored output |
| `--help`, `-h` | Show help |
| `--version`, `-v` | Print version and exit |

---

## Bundle commands

### vokun install

```
vokun install <bundle> [bundle...] [flags]
```

Install all packages from one or more bundles. Displays each package with its
description, marks AUR packages, and offers optional packages separately. Asks
for confirmation before proceeding. Supports multiple bundles in one command.

Already-installed packages are skipped (`--needed` is passed to pacman). Vokun
records which packages were actually new vs pre-existing, so `vokun remove`
only removes what vokun installed.

Bundles with `[select.*]` sections prompt you to pick one tool per category
(e.g., editor, shell, pager). The `--exclude` and `--only` flags also filter
select options.

**Conflict pre-flight check:** Before calling pacman, vokun checks each package
for conflicts via `pacman -Si`. If a conflicting package is already installed on
the system, vokun warns you before proceeding. This prevents unexpected package
removals during install.

After a successful install the bundle is recorded in the state file.

| Flag | Description |
|------|-------------|
| `--pick` | Interactively select which packages to install (fzf or numbered menu) |
| `--exclude pkg1,pkg2` | Skip specific packages from the bundle (applies to selects too) |
| `--only pkg1,pkg2` | Install only these packages from the bundle (applies to selects too) |
| `--dry-run` | Show what would be installed without making changes |
| `--yes`, `-y` | Skip confirmation prompt |

Examples:

```bash
vokun install coding                        # Install all packages
vokun install coding sysadmin               # Install multiple bundles
vokun install coding --pick                 # Choose individual packages
vokun install coding --exclude gdb,strace   # Skip gdb and strace
vokun install coding --only git,cmake       # Install only git and cmake
vokun install coding --dry-run              # Preview without installing
```

Skipped packages are recorded in the state file so vokun knows they were
intentionally excluded.

### vokun remove

```
vokun remove <bundle> [bundle...] [--dry-run] [--untrack] [--all]
```

By default, removes only packages that vokun actually installed for this bundle.
Pre-existing packages (already on your system before the bundle was installed)
are kept. Packages shared with other bundles are always kept. Supports multiple
bundles in one command.

| Flag | Description |
|------|-------------|
| `--dry-run` | Show what would be removed without making changes |
| `--untrack` | Remove the bundle from vokun tracking only, keep all packages on system |
| `--all` | Remove ALL bundle packages including pre-existing ones |

Examples:

```bash
vokun remove gaming                         # Remove only what vokun installed
vokun remove gaming coding                  # Remove multiple bundles
vokun remove sysadmin --untrack             # Stop tracking, keep packages
vokun remove sysadmin --all                 # Remove everything including pre-existing
vokun remove coding --dry-run               # Preview without removing
```

### vokun select

```
vokun select <bundle>
```

Change your pick-one selections for an installed bundle. Bundles with
`[select.*]` sections let you choose one tool per category (e.g., editor,
shell, pager). Shows current selections and prompts for new choices. Offers
to remove old selections after switching.

### vokun list

```
vokun list [--installed] [--names-only]
```

List all available bundles, grouped by their primary tag. Installed bundles are
highlighted.

| Flag | Description |
|------|-------------|
| `--installed` | Show only installed bundles |
| `--names-only` | Print bare names, one per line (used by completions) |
| `--deps` | List packages installed as dependencies (`pacman -Qd`) |

### vokun info

```
vokun info <bundle>
```

Show detailed information about a bundle: description, version, tags, and every
package with its description and current install status.

### vokun search

```
vokun search <keyword>
```

Search across all bundles by name, description, tags, and package names. Results
show the bundle name, description, and which field matched.

### vokun bundle

```
vokun bundle create <name>
vokun bundle add <bundle> <package>
vokun bundle rm <bundle> <package>
vokun bundle edit <bundle>
vokun bundle delete <bundle>
```

Manage custom bundles from the command line.

| Subcommand | Description |
|------------|-------------|
| `create` | Create a new custom bundle interactively. Supports `extends` for bundle composition. |
| `add` | Add a package to an existing custom bundle |
| `rm` | Remove a package from a custom bundle |
| `edit` | Open the bundle TOML file in your editor |
| `delete` | Delete a custom bundle entirely |

When creating a bundle, you can set `extends = "sysadmin"` in the `[meta]`
section to inherit all packages from another bundle (see
[Bundles documentation](bundles.md) for details).

### vokun rollback

```
vokun rollback
```

Undo the last reversible action. Reversible actions are: bundle install, bundle
remove, get, and yeet. Vokun shows what will be undone and asks for confirmation
before proceeding. The undo operation is itself logged to the action log.

Rollback uses the action log (`~/.config/vokun/vokun.log`) to determine the
most recent reversible action.

---

## Action log

### vokun log

```
vokun log [--count N]
```

Display recent entries from the action log. Every bundle install, remove, get,
yeet, rollback, and dotfiles action is automatically recorded to
`~/.config/vokun/vokun.log` with the format:

```
timestamp|action|target|details|profile
```

Entries are color-coded by action type (green for installs, red for removals).

| Flag | Description |
|------|-------------|
| `--count N` | Number of entries to show (default: 20) |

---

## Dotfile management

### vokun dotfiles

```
vokun dotfiles init
vokun dotfiles apply
vokun dotfiles push
vokun dotfiles pull
vokun dotfiles status
vokun dotfiles edit
```

Unified wrapper around chezmoi, yadm, or stow. The backend is auto-detected
(in that order of preference) or can be set explicitly via `dotfiles.backend` in
`vokun.conf`.

All destructive subcommands (apply, push, pull) show a preview of the changes
and require confirmation before proceeding.

| Subcommand | Description |
|------------|-------------|
| `init` | Initialize dotfile tracking with the detected backend |
| `apply` | Apply dotfiles to the system (shows preview, confirms) |
| `push` | Push local dotfile changes to the upstream repository |
| `pull` | Pull dotfile changes from the upstream repository |
| `status` | Show the current status of tracked dotfiles |
| `edit` | Open a tracked dotfile in your editor |

All dotfiles actions are recorded in the action log.

---

## Query & diagnostics

### vokun status

```
vokun status
```

Show a dashboard overview of your vokun setup: active profile,
installed/available bundle counts, tracked/system package counts, active
selections, untracked packages, and timestamps for the last system update and
sync.

### vokun why

```
vokun why <package>
```

Show which bundles include a given package and whether each bundle is currently
installed. If the package was installed via `vokun get` but never added to a
bundle, that is noted too.

Examples:

```bash
vokun why strace
# strace is included in:
#   coding (installed)
#   sysadmin (installed)
#   c-cpp-dev (not installed)

vokun why neovim
# neovim is not in any bundle.
# It was installed via vokun get and never added to a bundle.
```

### vokun untracked

```
vokun untracked
```

List packages that were installed via `vokun get` but never added to any bundle.
These are ad-hoc installs that should be formalized into a bundle or removed.

Each package is shown with its current install status. At the end, vokun
suggests using `vokun bundle add` to formalize them.

### vokun doctor

```
vokun doctor
```

Run all health checks in sequence and display a pass/warn/fail summary with
actionable next steps.

| Check | What it does |
|-------|-------------|
| Dependencies | Verifies required, recommended, and optional tools are installed |
| Sync drift | Detects forward drift (untracked packages) and reverse drift (tracked but missing) |
| Integrity | Checks for broken symlinks and missing dependencies |
| Orphans | Counts orphaned packages |
| Cache | Warns if the package cache exceeds 5 GB |
| Untracked | Counts ad-hoc installs from `vokun get` not in any bundle |

### vokun snapshot

```
vokun snapshot create <name>
vokun snapshot list
vokun snapshot diff <name>
vokun snapshot restore <name> [--dry-run]
vokun snapshot delete <name>
```

Save, compare, and restore system package snapshots. Each snapshot stores the
full `pacman -Qe` output plus current vokun state (installed bundles, profile)
in `~/.config/vokun/snapshots/`.

| Subcommand | Description |
|------------|-------------|
| `create <name>` | Save the current system state as a named snapshot |
| `list` | Show all saved snapshots with timestamps and package counts |
| `diff <name>` | Compare a snapshot against the current system (packages added/removed, bundles changed) |
| `restore <name>` | Install missing packages and remove extra packages to match the snapshot |
| `delete <name>` | Remove a saved snapshot |

| Flag | Description |
|------|-------------|
| `--dry-run` | Show what restore would do without making changes |
| `--yes`, `-y` | Skip confirmation prompts |

Examples:

```bash
vokun snapshot create before-cleanup       # Save current state
vokun snapshot list                        # See all snapshots
vokun snapshot diff before-cleanup         # What changed since then?
vokun snapshot restore before-cleanup --dry-run  # Preview restore
vokun snapshot restore before-cleanup      # Actually restore
vokun snapshot delete before-cleanup       # Clean up
```

---

## Package commands

These are convenience aliases around pacman (or your configured AUR helper).
Every command prints the underlying pacman invocation for transparency.

### vokun get

```
vokun get <package> [package...]
```

Install one or more packages. Uses paru/yay if available, otherwise pacman.
When `auto_prompt` is enabled (the default), vokun prompts after a successful
install to add the package to an existing bundle or create a new one.

Equivalent to: `sudo pacman -S --needed <package>`

### vokun yeet

```
vokun yeet <package> [package...] [--untrack]
```

Remove packages along with unneeded dependencies and configuration files. Warns
if a package belongs to an installed bundle.

| Flag | Description |
|------|-------------|
| `--untrack` | Remove the package from bundle tracking only, keep it installed |

Equivalent to: `sudo pacman -Rns <package>`

### vokun find

```
vokun find <query> [--aur] [--pick]
```

Search for packages in the sync repositories. Pass `--aur` to include AUR
results (requires paru or yay). Pass `--pick` to interactively select packages
from results and install them via `vokun get`.

| Flag | Description |
|------|-------------|
| `--aur` | Include AUR results |
| `--pick` | Interactively select packages to install (fzf or numbered menu) |

Equivalent to: `pacman -Ss <query>`

### vokun which

```
vokun which <package> [--remote]
```

Show detailed information about a package. By default queries locally installed
packages. Pass `--remote` to query the remote sync databases instead.

| Flag | Description |
|------|-------------|
| `--remote` | Query remote repo/AUR info (`pacman -Si`) |

Equivalent to: `pacman -Qi <package>` (or `pacman -Si` with `--remote`)

### vokun owns

```
vokun owns <file>
```

Find which installed package owns a file on the filesystem.

Equivalent to: `pacman -Qo <file>`

### vokun update

```
vokun update [--aur] [--aur-only] [--check]
```

Synchronize repositories and upgrade all packages. Pass `--aur` to also update
AUR packages through your configured helper. Pass `--aur-only` to update only
AUR packages without a full system update. Pass `--check` to only show
available upgrades without installing them.

| Flag | Description |
|------|-------------|
| `--aur` | Include AUR packages |
| `--aur-only` | Update only AUR packages (`paru/yay -Sua`) |
| `--check` | Show available upgrades without installing |

Examples:

```bash
vokun update                    # Full system update
vokun update --aur              # Include AUR packages
vokun update --aur-only         # AUR packages only
vokun update --check            # Just check for updates
vokun update --check --aur      # Check including AUR
vokun update --check --aur-only # Check only AUR updates
```

Equivalent to: `sudo pacman -Syu`

---

## Portability

### vokun export

```
vokun export [file] [--json]
```

Export your custom bundles and configuration to a portable file. Optionally
specify an output filename. By default the output is TOML; pass `--json` for
JSON format. The export includes custom bundle definitions from
`~/.config/vokun/bundles/custom/` and your `vokun.conf` settings.

### vokun import

```
vokun import <file> [--dry]
```

Import bundles and configuration from a previously exported file. Pass `--dry`
to preview the changes without writing anything to disk.

**Hook safety:** If any imported bundle contains `post_install` hooks, vokun
displays the commands for review before asking you to confirm the import. This
prevents blindly executing arbitrary shell commands from untrusted exports.

---

## Maintenance commands

### vokun orphans

```
vokun orphans [--clean] [--deep]
```

List packages that were installed as dependencies but are no longer required by
any installed package. Pass `--clean` to remove them. Pass `--deep` for
thorough cleanup including AUR build dependencies (`paru/yay -c`).

### vokun cache

```
vokun cache [--clean | --purge]
```

Without flags, shows cache location, package count, and total size.

| Flag | Description |
|------|-------------|
| `--clean` | Keep the last 2 versions of each cached package (`paccache -rk2`) |
| `--purge` | Remove all cached packages (`paccache -rk0`) |

Requires `pacman-contrib` for `--clean` and `--purge`.

### vokun history

```
vokun history [--search term...] [--installed|--removed|--upgraded|--downgraded] [--count N]
```

Show recent pacman transactions from `/var/log/pacman.log`. Color-coded by
action type. Use `--search` to find transactions matching specific packages —
useful for diagnosing issues after a system update.

| Flag | Description |
|------|-------------|
| `--search term [term...]` | Filter by package name (matches any term) |
| `--installed` | Show only package installs |
| `--removed` | Show only package removals |
| `--upgraded` | Show only package upgrades |
| `--downgraded` | Show only package downgrades |
| `--count N` | Number of entries (default: 50) |

Examples:

```bash
vokun history                              # Last 50 transactions
vokun history --search nvidia mesa sddm    # Display-related changes
vokun history --search plasma --upgraded   # Plasma upgrades only
vokun history --installed --count 100      # Last 100 installs
```

### vokun size

```
vokun size [--top N]
```

List installed packages sorted by installed size, largest first. Defaults to the
top 20.

### vokun recent

```
vokun recent [--count N]
```

Show the most recently installed packages from the pacman log. Defaults to 20
entries.

### vokun foreign

```
vokun foreign
```

List all packages not found in the sync databases (typically AUR-installed
packages).

Equivalent to: `pacman -Qm`

### vokun explicit

```
vokun explicit
```

List all explicitly installed packages (not pulled in as dependencies).

Equivalent to: `pacman -Qe`

---

## System Maintenance

### vokun broken

```
vokun broken
```

Scan the system for broken symlinks and missing shared-library dependencies.
Reports files that point to non-existent targets and packages whose libraries
cannot be resolved.

---

## Sync

### vokun sync

```
vokun sync [--auto] [--quiet]
```

Reconcile vokun's state with what is actually installed on the system. Sync
performs three checks:

1. **Forward sync** -- detects packages installed outside vokun (e.g. via
   `pacman -S`) that are not tracked in any bundle.
2. **Reverse sync** -- detects packages that were removed outside vokun (e.g.
   via `pacman -Rns`) but are still recorded in the state file.
3. **Drift detection** -- compares the installed state against current TOML
   bundle definitions to find packages that were added or removed upstream
   (for example, after updating vokun to a new version with modified bundles).

| Flag | Description |
|------|-------------|
| `--auto` | Automatically reconcile without prompting |
| `--quiet` | Suppress informational output |

---

## Profiles

### vokun profile

```
vokun profile show
vokun profile list
vokun profile switch <name>
vokun profile create <name>
vokun profile delete <name>
```

Manage installation profiles. Each profile maintains its own state file
(`state-<name>.json` in the config directory). The default profile uses
`state.json` for backwards compatibility.

| Subcommand | Description |
|------------|-------------|
| `show` | Display the name of the currently active profile |
| `list` | List all available profiles |
| `switch` | Switch to a different profile |
| `create` | Create a new empty profile |
| `delete` | Delete a profile and its state file |

The active profile is tracked in `~/.config/vokun/.active_profile`.

---

## AUR utilities

### vokun check

```
vokun check <package>
```

Query the AUR for trust information about a package: vote count, popularity,
last-updated date, maintainer, and out-of-date status. The result is compared
against the configured `trust_threshold` and `warn_age_days`.

### vokun diff

```
vokun diff <package>
```

Fetch and display the PKGBUILD for an AUR package. Useful for reviewing what
a package does before installing it.

---

## Automation

### vokun hook

```
vokun hook install [--dry-run]
vokun hook remove  [--dry-run]
```

Manage the pacman notification hook. The hook prints a reminder to run
`vokun sync` whenever packages are installed outside of vokun.

| Subcommand | Description |
|------------|-------------|
| `install` | Install the pacman hook to `/etc/pacman.d/hooks/` |
| `remove` | Remove the previously installed hook |

Pass `--dry-run` to see what would be done without making changes.

### vokun setup

```
vokun setup
```

Check that all required and optional dependencies are present. If `paru` is
not installed, offers to bootstrap it from the AUR. This is useful after a
fresh install or when setting up a new machine.

### vokun uninstall

```
vokun uninstall
```

Remove vokun from the system. Detects whether vokun was installed via pacman
(AUR package) or manually (make install) and uses the appropriate removal
method. Shows hints about cleaning up the config directory
(`~/.config/vokun`) and AUR build cache (`~/.cache/paru/clone/vokun`).
