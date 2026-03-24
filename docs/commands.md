---
layout: default
title: Command Reference
nav_order: 3
---

# Command Reference

## Interactive mode

Running `vokun` with no arguments launches an interactive menu powered by `fzf`
(or numbered fallback). From there you can browse bundles, install, remove, and
access every command without memorizing subcommands.

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
vokun install <bundle> [flags]
```

Install all packages from a bundle. Displays each package with its description,
marks AUR packages, and offers optional packages separately. Asks for
confirmation before proceeding.

Already-installed packages are skipped (`--needed` is passed to pacman).

After a successful install the bundle is recorded in the state file.

| Flag | Description |
|------|-------------|
| `--pick` | Interactively select which packages to install (fzf or numbered menu) |
| `--exclude pkg1,pkg2` | Skip specific packages from the bundle |
| `--only pkg1,pkg2` | Install only these packages from the bundle |
| `--dry-run` | Show what would be installed without making changes |
| `--yes`, `-y` | Skip confirmation prompt |

Examples:

```bash
vokun install coding                        # Install all packages
vokun install coding --pick                 # Choose individual packages
vokun install coding --exclude gdb,strace   # Skip gdb and strace
vokun install coding --only git,cmake       # Install only git and cmake
vokun install coding --dry-run              # Preview without installing
```

Skipped packages are recorded in the state file so vokun knows they were
intentionally excluded.

### vokun remove

```
vokun remove <bundle> [--dry-run]
```

Remove packages that are unique to the given bundle. Packages shared with other
installed bundles are kept and listed. The bundle is removed from the state file
after the operation.

Use `--dry-run` to preview what would be removed without making changes.

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

---

## Package commands

These are convenience aliases around pacman (or your configured AUR helper).
Every command prints the underlying pacman invocation for transparency.

### vokun get

```
vokun get <package> [package...]
```

Install one or more packages. Uses paru/yay if available, otherwise pacman.
After a successful install, optionally prompts to add the package to a bundle.

Equivalent to: `sudo pacman -S --needed <package>`

### vokun yeet

```
vokun yeet <package> [package...]
```

Remove packages along with unneeded dependencies and configuration files. Warns
if a package belongs to an installed bundle.

Equivalent to: `sudo pacman -Rns <package>`

### vokun find

```
vokun find <query> [--aur]
```

Search for packages in the sync repositories. Pass `--aur` to include AUR
results (requires paru or yay).

Equivalent to: `pacman -Ss <query>`

### vokun which

```
vokun which <package>
```

Show detailed information about an installed package.

Equivalent to: `pacman -Qi <package>`

### vokun owns

```
vokun owns <file>
```

Find which installed package owns a file on the filesystem.

Equivalent to: `pacman -Qo <file>`

### vokun update

```
vokun update [--aur]
```

Synchronize repositories and upgrade all packages. Pass `--aur` to also update
AUR packages through your configured helper.

Equivalent to: `sudo pacman -Syu`

---

## Portability

### vokun export

```
vokun export [--json]
```

Export your custom bundles and configuration to a portable file. By default the
output is TOML; pass `--json` for JSON format. The export includes custom bundle
definitions from `~/.config/vokun/bundles/custom/` and your `vokun.conf`
settings.

### vokun import

```
vokun import <file> [--dry]
```

Import bundles and configuration from a previously exported file. Pass `--dry`
to preview the changes without writing anything to disk.

---

## Maintenance commands

### vokun orphans

```
vokun orphans [--clean]
```

List packages that were installed as dependencies but are no longer required by
any installed package. Pass `--clean` to remove them.

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
