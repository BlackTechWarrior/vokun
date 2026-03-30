---
layout: default
title: Things to Know
nav_order: 6
---

# Things to Know

Vokun wraps pacman with friendlier commands and adds bundle management on top.
Most of it works the way you'd expect, but a few behaviors are worth calling out.

---

## Bundle commands vs package commands

Vokun separates **metadata operations** from **package operations**. The
`bundle` subcommands (`create`, `add`, `rm`, `edit`, `delete`) only touch the
TOML definition files. They never install or remove packages from the system.

The top-level commands (`install`, `remove`, `sync`, `rollback`) are the ones
that actually interact with pacman.

| Command | What it does |
|---------|-------------|
| `vokun bundle add coding git` | Adds `git` to the TOML file for `coding` |
| `vokun install coding` | Installs all packages listed in `coding` |
| `vokun bundle delete coding` | Deletes the TOML file — does **not** remove packages |
| `vokun remove coding` | Removes packages that vokun installed for `coding` |

If you want to delete a custom bundle **and** its packages, run `vokun remove`
first, then `vokun bundle delete`.

---

## vokun remove only removes what vokun installed

When you install a bundle, vokun records which packages were **newly installed**
versus which were **already on your system**. When you later run `vokun remove`,
only the packages that vokun actually installed are removed. Pre-existing
packages are kept.

Use `--all` to override this and remove everything in the bundle regardless of
origin. Use `--untrack` to stop tracking a bundle without removing any packages.

---

## --overwrite and --downgrade are direct-package-only

Both `vokun get --overwrite` and `vokun get --downgrade` are escape hatches for
specific problems (file conflicts and bad updates, respectively). They only work
with `vokun get`, not through bundle installs. This is intentional — bundle
installs go through a different workflow with conflict pre-flight checks.

---

## Downgrading AUR packages is not supported

`vokun get --downgrade` checks the local pacman cache first, then falls back to
the Arch Linux Archive (ALA) for official repo packages. AUR packages are not in
the ALA — they are built locally from source. To downgrade an AUR package, you
need to check out an older commit from the AUR git repo and rebuild it manually
with your AUR helper.

---

## After downgrading, the next update will re-upgrade

When you downgrade a package with `vokun get --downgrade`, the next
`vokun update` will upgrade it back to the latest version. If you need to keep
the older version, add the package to `IgnorePkg` in `/etc/pacman.conf`:

```
IgnorePkg = mesa
```

Vokun reminds you of this after every downgrade.

---

## vokun get prompts to add packages to a bundle

After a successful `vokun get`, you are prompted to add the package to a bundle.
This keeps ad-hoc installs organized. You can type a bundle name, `new` to
create one, or `n` to skip.

Disable this with `auto_prompt = false` in `vokun.conf`.

---

## vokun yeet blocks removal of bundle-tracked packages

If you `vokun yeet` a package that belongs to an installed bundle, vokun blocks
the removal to prevent silent drift between your bundles and your system. Use
`--force` to override — this removes the package and updates the bundle's state
to reflect the change. Use `--untrack` to remove the package from bundle
tracking without touching the system.

---

## Rollback is single-step

`vokun rollback` undoes the **most recent** reversible action only. It is not a
full undo history. Reversible actions are:

- `get` (package install)
- `yeet` (package removal)
- `bundle-install` (bundle install)
- `bundle-remove` (bundle removal)

Actions like `sync`, `snapshot restore`, and `bundle delete` are not reversible
through rollback.

---

## Bundle extends is single-level

A bundle can use `extends = "parent"` in its `[meta]` section to inherit
packages from another bundle. However, the parent bundle cannot itself extend
another bundle. This is a deliberate single-level restriction to keep bundle
resolution simple and predictable.

---

## Partial AUR updates warn you

Running `vokun update --aur-only` updates AUR packages without a full system
update (`pacman -Syu`). This can cause dependency mismatches between AUR packages
and system libraries. Vokun warns you about this and offers to run a full update
instead. If you proceed anyway, you accept the risk.

---

## Snapshots match packages, not versions

`vokun snapshot restore` ensures that the same set of packages is installed, but
it does not pin or restore specific package versions. If you created a snapshot
with `mesa 24.1` and later upgraded to `mesa 24.2`, restoring that snapshot will
keep `mesa 24.2` because the package is already present. Snapshots are about
**which packages** are on your system, not **which versions**. To pin a specific
version, add the package to `IgnorePkg` in `/etc/pacman.conf`.

---

## Dependencies and vokun setup

Vokun works with just `pacman`, `bash`, and `curl`, but several features require
optional dependencies:

| Dependency | What breaks without it |
|---|---|
| `jq` | State tracking, sync, export/import, AUR checking, profiles |
| `fzf` | Interactive pickers (falls back to numbered menus) |
| `paccache` | Cache management (`vokun cache --clean/--purge`) |
| `paru`/`yay` | AUR installs, `--aur` flags, `vokun check`/`diff` |

If a missing dependency blocks a command, vokun points you to `vokun setup`,
which checks all dependencies and offers to install anything missing.
