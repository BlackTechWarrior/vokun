# Contributing to Vokun

Thanks for your interest in contributing. This document covers the conventions
and process for submitting changes.

---

## Adding a bundle

1. Create a TOML file in `bundles/` (see any existing file for the format).
2. Every package must have a description value -- this is shown to users during
   install and should explain *why* the package is useful.
3. Put AUR packages under `[packages.aur]` and nice-to-haves under
   `[packages.optional]`.
4. Tag your bundle with relevant keywords in `meta.tags` so it appears in
   search results.
5. Test locally: `vokun info <your-bundle>` and `vokun install <your-bundle>`.

---

## Coding style

- **Shellcheck clean.** All scripts must pass `shellcheck -s bash` with no
  warnings. Run `make lint` before submitting.
- **Function naming.** Use the `vokun::module::function` convention. Functions
  in `lib/core.sh` are `vokun::core::*`, functions in `lib/bundles.sh` are
  `vokun::bundles::*`, and so on.
- **Quoting.** Always quote variables: `"$var"`, not `$var`.
- **Transparency.** Any command that modifies the system must call
  `vokun::core::show_cmd` first so the user can see exactly what is being run.
- **No external dependencies in core.** The core tool depends only on Bash 4+
  and pacman. Optional features (fzf, jq) degrade gracefully when absent.
- **Color.** Use the `VOKUN_COLOR_*` variables from `lib/core.sh`. Respect the
  `--no-color` flag and the `NO_COLOR` environment variable.

---

## Testing

Run the test suite with:

```bash
make test
```

Tests live in the `tests/` directory. When adding a new feature, add at least a
basic test that exercises the happy path.

---

## Pull request process

1. Fork the repository and create a branch from `main`.
2. Make your changes. Keep commits focused -- one logical change per commit.
3. Run `make lint` and `make test`.
4. Open a pull request with a clear title and a short description of what your
   change does and why.
5. A maintainer will review your PR. Small fixes are usually merged quickly;
   larger changes may go through a round or two of feedback.

---

## Reporting issues

Open an issue on GitHub. Include:

- What you expected to happen.
- What actually happened (paste terminal output if relevant).
- Your distro and AUR helper (`paru --version` or `yay --version`).
