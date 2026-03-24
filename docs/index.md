---
layout: default
title: Home
nav_order: 1
permalink: /
---

# Vokun

**Task-oriented package bundle manager for Arch Linux.**

Vokun wraps `pacman`, `paru`, and `yay` to let you install curated groups of
packages -- called **bundles** -- with a single command. It ships with 24
default bundles covering development, system administration, networking,
multimedia, gaming, and more.

Everything vokun does is transparent: it always shows the underlying pacman
command, never installs anything without confirmation, and stores packages as
regular system packages with no lock-in.

---

## Highlights

- **Pure Bash** -- zero dependencies beyond pacman. Optionally uses paru/yay
  for AUR support.
- **24 default bundles** -- coding, sysadmin, python-dev, c-cpp-dev, rust-dev,
  web-dev, networking, security, multimedia, gaming, and more.
- **Custom bundles** -- define your own in a simple TOML file.
- **Friendly aliases** -- `vokun get`, `vokun yeet`, `vokun update` instead
  of memorizing pacman flags.
- **Tab completion** -- Bash and Fish completions ship out of the box.

---

## Quick start

```bash
paru -S vokun              # Install from the AUR
vokun list                 # Browse available bundles
vokun install sysadmin     # Install the sysadmin toolkit
```

See the [Getting Started](getting-started) guide for full installation
instructions, or jump to the [Command Reference](commands) for details on every
command.
