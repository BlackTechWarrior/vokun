---
layout: default
title: Command Reference
nav_order: 3
---

# Command Reference

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
vokun install <bundle> [--yes]
```

Install all packages from a bundle. Displays each package with its description,
marks AUR packages, and offers optional packages separately. Asks for
confirmation before proceeding.

Already-installed packages are skipped (`--needed` is passed to pacman).

After a successful install the bundle is recorded in the state file.

### vokun remove

```
vokun remove <bundle>
```

Remove packages that are unique to the given bundle. Packages shared with other
installed bundles are kept and listed. The bundle is removed from the state file
after the operation.

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
