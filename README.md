# archinit

A self-installing, idempotent Arch Linux initialization tool.
`install.sh` bootstraps into `~/.archinit`; the `archinit` command runs idempotent
modules either via subcommands (CLI) or an interactive TUI.

Runs after `archinstall` (partitions, network, audio assumed ready).

## Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/alexjoedt/archinit/main/install.sh | bash
```

Then open a new shell and run:

```bash
archinit        # interactive TUI module selector
archinit install # install all configured modules
```

## CLI Reference

```
archinit [FLAGS] <command> [args]

Commands:
  install   [module...]   Install modules (default: DEFAULT_MODULES or all)
  update                  Self-update archinit and re-run pending modules
  doctor                  Read-only health/drift report (exit 1 if any fails)
  list                    List modules with class and status
  snapshot  [create|list|show [NAME]]  Capture/list package snapshots
  restore   [NAME]        Reinstall packages from a snapshot
  config    [key [value]] View or set configuration keys
  tui                     Interactive module selector (default with no args)
  version                 Print version information
  uninstall               Remove archinit (installed packages kept)

Global flags:
  --dry-run   --verbose   --quiet   --yes   --no-color   --force
```

Every command also supports `--help`:

```bash
archinit install --help
archinit snapshot --help
```

## Architecture

```
archinit/
├── install.sh              # bootstrap: git clone/update + shell hook
├── bin/archinit            # CLI entrypoint
├── VERSION
├── lib/                    # sourced libraries (no side effects on source)
│   ├── core.sh  log.sh  ui.sh  os.sh  pkg.sh  service.sh  fs.sh
│   ├── config.sh  state.sh  update.sh  install.sh  snapshot.sh
│   ├── git.sh  dotfiles.sh
├── cmd/                    # one file per verb
│   ├── install.sh  update.sh  doctor.sh  tui.sh  list.sh  version.sh
│   ├── snapshot.sh  restore.sh  config.sh  uninstall.sh
├── modules/                # idempotent units, numbered
│   ├── 00-base/     10-aur-helper/  20-services/
│   ├── 30-desktop/  35-git/         40-dev/
├── config/
│   ├── defaults.conf
│   └── packages/
│       ├── base.txt        # official base packages
│       ├── desktop.txt     # Hyprland Wayland stack
│       └── aur.txt         # AUR packages (requires yay)
├── shell/archinit.sh       # rc hook: PATH + throttled auto-update
└── tests/
    ├── lint.sh             # shellcheck + shfmt
    └── bats/               # bats-core unit tests
```

## Package Classes

| Class   | Source         | Installer              | List file                    |
|---------|----------------|------------------------|------------------------------|
| base    | official repos | `pacman -S --needed`   | `config/packages/base.txt`   |
| desktop | official repos | `pacman -S --needed`   | `config/packages/desktop.txt`|
| aur     | AUR            | `yay -S --needed`      | `config/packages/aur.txt`    |

Edit the list files to customize packages. One package per line; `#` comments
and blank lines are ignored.

## Modules

| Module     | Class   | Description                                      |
|------------|---------|--------------------------------------------------|
| base       | base    | Core CLI and system packages                     |
| aur-helper | base    | Bootstrap yay from AUR source                   |
| services   | service | Enable NetworkManager, pipewire, etc.            |
| desktop    | desktop | Hyprland Wayland stack + sddm display manager   |
| git        | base    | Git identity, SSH/token auth, optional gh CLI   |
| dev        | aur     | AUR dev tools + dotfiles via dman               |

Modules are idempotent: `module_check` gates re-runs. Use `--force` to re-run.

Module dependencies are resolved topologically via `module_requires` — running
`archinit install dev` automatically runs `aur-helper` and `git` first.

## Snapshots

```bash
archinit snapshot          # capture current explicit packages
archinit snapshot list     # list snapshots newest-first
archinit snapshot show     # print contents of latest snapshot
archinit restore           # reinstall packages from latest snapshot
archinit restore 2026-06-10T14-30-00  # restore specific snapshot
```

Snapshots are stored under `~/.local/state/archinit/snapshots/` (XDG state).
They are **never written into the git clone**. Track `latest/` in your dman
dotfiles repo to make your package set portable across machines.

## Configuration

```bash
archinit config                    # list all keys
archinit config GIT_USER_EMAIL     # print a key
archinit config DOTFILES_REPO https://github.com/you/dotfiles.git
archinit config --unset DOTFILES_REPO
```

Settings are written to `~/.archinit/config.local`; `config/defaults.conf`
is never modified.

Key settings:

| Key                        | Default    | Description                         |
|----------------------------|------------|-------------------------------------|
| `UPDATE_INTERVAL_HOURS`    | 24         | Auto-update throttle (hours)        |
| `DEFAULT_MODULES`          | base aur-helper services | Modules for bare `install` |
| `AUR_HELPER`               | yay        | AUR helper to use                   |
| `DOTFILES_MANAGER`         | dman       | Dotfile manager backend             |
| `DOTFILES_REPO`            | ""         | Dotfiles git repo URL               |
| `INSTALL_SNAPSHOT_PACKAGES`| true       | Merge latest snapshot on install    |
| `GIT_AUTH_METHOD`          | ssh        | Git auth: ssh \| token \| skip      |
| `SETUP_GH_CLI`             | true       | Offer gh CLI setup in git module    |

## Runtime State (XDG)

The git clone `~/.archinit` is read-only-ish; all machine state is under:

```
~/.local/state/archinit/
├── .last_update          # auto-update throttle timestamp
├── .state/               # module completion markers
├── logs/                 # per-run logs (<ISO-ts>.log) + latest.log symlink
├── secrets.local         # GitHub token if stored (chmod 600, gitignored)
└── snapshots/
    ├── 2026-06-10T14-30-00/
    │   ├── native.txt    # pacman -Qqen (official explicit)
    │   └── foreign.txt   # pacman -Qqem (AUR explicit)
    └── latest -> 2026-06-10T14-30-00
```

## Self-Update

archinit self-updates via `git pull --ff-only` on shell open (throttled to
once per `UPDATE_INTERVAL_HOURS`). Local changes are detected and never
clobbered — a warning is printed instead.

Trigger manually: `archinit update`

## Development

```bash
# Lint
bash tests/lint.sh

# Unit tests (requires bats-core)
bats tests/bats/

# Type-check all scripts
bash -n bin/archinit lib/*.sh cmd/*.sh modules/*/module.sh
```

## Uninstall

```bash
archinit uninstall           # removes ~/.archinit + shell hook; keeps packages
archinit uninstall --purge   # also removes ~/.local/state/archinit
```

Dotfiles backed up by `lib/fs.sh` are kept as `*.archinit.bak.<ts>` files.

```bash
curl -fsSL https://raw.githubusercontent.com/alexjoedt/archinit/main/install.sh | bash

```