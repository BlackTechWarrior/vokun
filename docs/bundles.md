---
layout: default
title: Bundles
nav_order: 4
---

# Bundles

A bundle is a TOML file that defines a group of packages organized around a
task. Vokun ships with 19 default bundles and supports user-created custom
bundles.

---

## Bundle locations

| Location | Purpose |
|----------|---------|
| `/usr/share/vokun/bundles/` (or `/usr/local/share/vokun/bundles/`) | Default bundles shipped with vokun |
| `~/.config/vokun/bundles/custom/` | User-created bundles |

Custom bundles appear alongside defaults in `vokun list` and `vokun search`.

---

## TOML format

```toml
[meta]
name = "Bundle Display Name"
description = "One-line description shown in vokun list and vokun info"
tags = ["tag1", "tag2", "tag3"]
version = "1.0.0"

[packages]
package-name = "Why this package is included"
another-pkg = "Description shown during install"

[packages.aur]
aur-package = "AUR packages are flagged and require paru or yay"

[packages.optional]
optional-pkg = "Offered during install but not selected by default"

[hooks]
post_install = [
    "echo 'Commands to run after a successful install'"
]
```

### Sections

**`[meta]`** -- Required. Provides the bundle identity.

- `name` -- Human-readable display name.
- `description` -- Short description. Shown in list and info output.
- `tags` -- Array of keywords. Used by `vokun search` and used to group bundles
  in `vokun list`. The first tag is treated as the primary category.
- `version` -- Semantic version string.

**`[packages]`** -- Core packages from the official Arch repositories. Each key
is a package name and each value is a description string. Descriptions are
displayed during install so users understand what each package does.

**`[packages.aur]`** -- Packages from the AUR. These are handled by the
configured AUR helper (paru or yay). If no AUR helper is available, these
packages are skipped with a warning. AUR packages are visually distinguished
during install.

**`[packages.optional]`** -- Packages that are useful but not essential. During
`vokun install`, the user is asked whether to include optional packages after
the core package list is shown.

**`[hooks]`** -- `post_install` is an array of shell commands that run after all
packages have been installed. Use this for setup hints or one-time configuration
commands.

---

## Creating a custom bundle

1. Create a TOML file in `~/.config/vokun/bundles/custom/`:

   ```bash
   mkdir -p ~/.config/vokun/bundles/custom
   nano ~/.config/vokun/bundles/custom/my-tools.toml
   ```

2. Write the bundle definition following the format above.

3. Verify it works:

   ```bash
   vokun info my-tools       # Check that parsing works
   vokun install my-tools    # Install it
   ```

The bundle is available immediately -- no registration or build step is needed.

---

## Tips

- Keep descriptions concise but informative. They are the main thing users see
  when deciding whether to install a package.
- Use `[packages.optional]` for large or opinionated packages. Let the user
  decide.
- Put AUR packages in `[packages.aur]` even if the user's AUR helper can
  install them transparently. The separation lets vokun warn about AUR trust.
- Tag your bundles well. Multiple tags help `vokun search` surface your bundle
  for different queries.

---

## Default bundles

Run `vokun list` to see all shipped bundles, or see the catalog table in the
[README](https://github.com/blacktechwarrior/vokun#default-bundle-catalog).
