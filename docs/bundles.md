---
layout: default
title: Bundles
nav_order: 4
---

# Bundles

A bundle is a TOML file that defines a group of packages organized around a
task. Vokun ships with 24 default bundles and supports user-created custom
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
extends = "parent-bundle"              # optional: string or array

[packages]
package-name = "Why this package is included"
another-pkg = "Description shown during install"

[packages.aur]
aur-package = "AUR packages are flagged and require paru or yay"

[packages.optional]
optional-pkg = "Offered during install but not selected by default"

[hooks]
pre_install = ["echo 'Before installing packages'"]
post_install = ["echo 'After installing packages'"]
pre_remove = ["echo 'Before removing packages'"]
post_remove = ["echo 'After removing packages'"]
```

### Sections

**`[meta]`** -- Required. Provides the bundle identity.

- `name` -- Human-readable display name.
- `description` -- Short description. Shown in list and info output.
- `tags` -- Array of keywords. Used by `vokun search` and used to group bundles
  in `vokun list`. The first tag is treated as the primary category.
- `version` -- Semantic version string.
- `extends` -- (Optional) Name of another bundle to inherit from. All packages
  from the parent bundle are included automatically, and the child bundle can
  add or override packages. See [Bundle extends](#bundle-extends) below.

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

**`[hooks]`** -- Arrays of shell commands that run at specific lifecycle points.
All hook commands are shown to the user and require confirmation before
execution.

| Hook | When it runs |
|------|-------------|
| `pre_install` | Before packages are installed |
| `post_install` | After all packages have been installed |
| `pre_remove` | Before packages are removed |
| `post_remove` | After packages have been removed |

```toml
[hooks]
pre_install = ["echo 'Preparing installation...'"]
post_install = ["echo 'Setup complete.'"]
pre_remove = ["echo 'Backing up config...'"]
post_remove = ["echo 'Cleanup complete.'"]
```

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

## Bundle extends (mixins)

A bundle can inherit all packages from one or more parent bundles using the
`extends` field in `[meta]`. This enables bundle composition -- build
specialized bundles on top of general-purpose ones without duplicating package
lists.

### Single parent

```toml
[meta]
name = "Full-Stack Dev"
description = "Web development plus sysadmin essentials"
tags = ["dev", "fullstack"]
version = "1.0.0"
extends = "sysadmin"

[packages]
nodejs = "JavaScript runtime"
npm = "Node.js package manager"
```

### Multiple parents (mixins)

The `extends` field also accepts an array for multi-parent inheritance:

```toml
[meta]
name = "DevOps Engineer"
description = "Sysadmin tools plus container and cloud tooling"
tags = ["devops", "fullstack"]
version = "1.0.0"
extends = ["sysadmin", "vm-container"]

[packages]
ansible = "IT automation platform"
```

In this example, installing `devops-engineer` would install all packages from
both `sysadmin` and `vm-container` plus `ansible`. The parents' AUR and
optional packages are also inherited.

### Resolution rules

- **Flat union** -- All parent packages are merged into one set.
- **Last-writer-wins** -- If two parents define the same package with different
  descriptions, the last parent in the array wins.
- **Child overrides** -- Packages defined in the child always override parent
  descriptions.
- **Single-level only** -- Parents cannot themselves have `extends`. If a parent
  has `extends`, it is ignored with a warning.
- **Cycle detection** -- If bundle A extends B and B extends A, vokun reports an
  error.
- **Parent must exist** -- Referenced parent bundles must exist (default or custom).

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

## Default bundle catalog

Vokun ships with 24 default bundles. This table is generated from the actual
TOML files in the repository.

| Bundle | Description | Tags | Packages |
|--------|-------------|------|----------|
| `browsers` | Web browsers for everyday browsing, privacy, and development | desktop, web, browsers | 5 |
| `c-cpp-dev` | Compilers, debuggers, and static analysis tools for C and C++ development | dev, c, cpp, systems | 9 |
| `cloud-tools` | Kubernetes management, infrastructure-as-code, and cloud CLI utilities | devops, cloud | 4 |
| `coding` | Essential compilers, debuggers, and development utilities for any programmer | dev, essentials | 13 |
| `communication` | Messaging, video conferencing, and team collaboration applications | desktop, social, communication | 6 |
| `embedded` | Cross-compilers, debuggers, and serial tools for embedded and ARM development | dev, embedded, hardware | 7 |
| `fonts` | Programming fonts and international font families for a polished desktop experience | desktop, appearance | 5 |
| `fpga-dev` | Open-source FPGA synthesis, simulation, and place-and-route tools | dev, fpga, hardware | 5 |
| `gaming` | Game launchers, compatibility layers, and performance tools for Linux gaming | gaming, fun | 6 |
| `go-dev` | Go compiler and language server for Go development | dev, go | 2 |
| `java-dev` | Java Development Kit and build tools for JVM-based development | dev, java | 3 |
| `latex` | TeX typesetting system, bibliography tools, and document converters for academic work | writing, academic | 5 |
| `media-playback` | Video and audio players for local media files and streaming services | desktop, media, entertainment | 7 |
| `multimedia` | Audio, video, and image processing tools for media creation and conversion | media, creative | 7 |
| `networking` | Network analysis, diagnostics, and security scanning utilities | net, admin | 10 |
| `office` | Document editing, email, PDF viewing, and spell checking for everyday productivity | productivity, office | 8 |
| `photo-editing` | Image editors, RAW processors, and photo management tools for photographers and artists | creative, photography, media | 7 |
| `python-dev` | Python interpreter, package management, linting, and testing tools | dev, python | 7 |
| `rust-dev` | Rust toolchain manager and essential cargo extensions for Rust development | dev, rust, systems | 4 |
| `security` | Offensive security and penetration testing tools for ethical hacking | sec, hacking, pentesting | 8 |
| `sysadmin` | Modern CLI utilities for system monitoring, file management, and productivity | admin, essentials, cli | 16 |
| `terminal-rice` | Shell frameworks, prompt themes, and terminal tools for a beautiful CLI setup | desktop, rice, terminal | 6 |
| `vm-container` | Container runtimes, virtual machine managers, and infrastructure provisioning tools | devops, infra | 6 |
| `web-dev` | JavaScript and TypeScript runtimes and package managers for web development | dev, web, js | 4 |

Run `vokun list` to see installed status, or `vokun info <bundle>` for full details.
