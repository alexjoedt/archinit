---
description: "Use when writing, editing, or adding to archinit shell scripts, modules, lib functions, or cmd handlers. Covers project architecture, shell conventions, module structure, and idempotency patterns."
---

# archinit Codebase Instructions

## Project Goal

`archinit` automates bringing a fresh Arch Linux installation (after `archinstall` has done partitioning/network/audio) to a fully configured, ready-to-work developer system. It installs packages, enables services, configures git, applies dotfiles, and manages package snapshots — all idempotently.

## Shell Conventions

- Shebang: `#!/usr/bin/env bash`
- Every file that runs code starts with `set -euo pipefail` and `IFS=$'\n\t'` (or sources `lib/core.sh` which sets these)
- Double-source guard on every library: `[[ -n ${_ARCHINIT_FOO:-} ]] && return 0` followed by `_ARCHINIT_FOO=1`
- Use `[[ ]]` for conditionals, never `[ ]`
- Quote all variable expansions: `"$var"`, `"${var}"` 
- Prefer `command -v` over `which`
- Use `# ---` section dividers with a blank line above and below, like existing files
- Comments: one-liner `# verb noun` style; avoid over-commenting obvious code
- `shellcheck source=/dev/null` before every sourced file

## Logging

Always use the `lib/log.sh` functions — never `echo` directly for user output:

| Function     | When to use                         |
|--------------|-------------------------------------|
| `log_info`   | Normal progress messages            |
| `log_ok`     | Success confirmations               |
| `log_warn`   | Non-fatal issues or skipped steps   |
| `log_error`  | Errors (before `die` or `return 1`) |
| `log_debug`  | Verbose/dev details (gated by `$VERBOSE`) |

## Error Handling

- Use `die "message"` (from `lib/core.sh`) for fatal errors
- Use `require_cmd CMD` to assert external tools exist before use
- Use `run CMD [ARGS]` for any mutating command so `--dry-run` is respected
- Use `as_root CMD` instead of hard-coding `sudo` — handles root context automatically

## Module Structure

Every module lives in `modules/<NN>-<name>/module.sh` and must define these exact functions:

```bash
module_name()     { echo "short-name"; }          # matches directory name without NN-
module_class()    { echo "base|aur|service|..."; }
module_describe() { echo "One-line human description"; }
module_requires() { echo "space-separated module names or empty string"; }

module_check() {
  # Read-only. Return 0 if already satisfied, 1 if install is needed.
  # Called by doctor too — must have zero side effects.
}

module_install() {
  assert_arch        # guard: abort if not Arch Linux
  # Idempotent install logic. Use pkg_install_list, pkg_is_installed, etc.
}
```

- Guard every `source` with the double-source pattern at the top
- Only source libs the module actually uses
- Dependencies declared in `module_requires` are automatically installed first — don't re-implement them

## Library Files (`lib/`)

- Each lib exposes a focused set of public functions (prefixed by domain: `pkg_`, `log_`, `config_`, `fs_`, etc.)
- Private helpers are prefixed with `_`
- No side effects on source — guards + variable init only; no function calls at top level
- Add new libs only when a cross-cutting concern isn't already covered

## Idempotency Rules

1. Every `module_check` must be a pure read-only test
2. `module_install` must be safe to call multiple times (use `--needed` with pacman/yay, check before creating files, etc.)
3. State markers live under `$ARCHINIT_STATE/.state/` — never inside the git clone
4. Never write machine state into `config/` or any tracked file

## Config & State Paths

| Variable           | Path                                      | Purpose                     |
|--------------------|-------------------------------------------|-----------------------------|
| `ARCHINIT_HOME`    | `~/.archinit` (git clone)                 | Read-only source            |
| `ARCHINIT_STATE`   | `~/.local/state/archinit`                 | All runtime/machine state   |
| `config_get KEY`   | reads `config/defaults.conf` + `config.local` | Runtime configuration |

Never hardcode `~/.archinit` or `~/.local/state/archinit` — always use the variables.

## Adding a New Module

1. Create `modules/<NN>-<name>/module.sh` following the structure above
2. Pick a number that places it after its dependencies (e.g., `50-` comes after `40-dev`)
3. Declare deps in `module_requires`
4. Add a `module_check` before writing any install logic
5. Run `bash -n modules/<NN>-<name>/module.sh` and `shellcheck` before committing

## Build & Test Commands

```bash
# Syntax-check all scripts
bash -n bin/archinit lib/*.sh cmd/*.sh modules/*/module.sh

# Lint (shellcheck + shfmt)
bash tests/lint.sh

# Unit tests (requires bats-core)
bats tests/bats/
```

## Package Lists

- `config/packages/base.txt` — official-repo base packages
- `config/packages/desktop.txt` — Hyprland/Wayland stack
- `config/packages/aur.txt` — AUR packages

One package per line; `#` lines and blank lines are ignored. Use `pkg_read_list` to consume them.
