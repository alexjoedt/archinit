# Plan: archinit — Self-Installing, Idempotent Arch Init (CLI + TUI)

**Status**: pending
**Created**: 2026-06-09
**Stack**: Bash (POSIX-ish / Bash 5), pacman, systemd, git; lint via shellcheck + shfmt; tests via bats-core

## Summary
Build an oh-my-zsh-style, self-installing/self-updating Arch initialization tool. `install.sh` bootstraps into `~/.archinit`; the `archinit` command runs idempotent modules either via subcommands/flags (CLI) or an interactive TUI. Packages are split into three classes: **base** (official, core system), **desktop** (official, Hyprland Wayland stack), and **aur** (installed via `yay`). Dotfiles are managed by **dman** (`github.com/alexjoedt/dman`) behind a swappable abstraction. Run after `archinstall` (partitions, network, audio assumed ready).

## Success Criteria
- [ ] `curl -fsSL .../install.sh | bash` clones to `~/.archinit`, adds a shell hook, is re-runnable
- [ ] `archinit` (no args) launches a TUI module selector
- [ ] `archinit install [module...]`, `update`, `doctor`, `list`, `version` work as CLI
- [ ] `archinit snapshot` captures explicit packages to XDG state; `archinit restore` reinstalls them idempotently
- [ ] `archinit config`, `archinit uninstall`, and per-subcommand `--help` work
- [ ] git module sets up identity + auth (HTTPS-token / SSH key / skip) and optional `gh auth`; secrets never logged
- [ ] Per-run logs written under `~/.local/state/archinit/logs/`; one failing package doesn't abort the run
- [ ] Module dependencies resolved topologically (e.g. `dev` pulls `aur-helper`+`git`)
- [ ] All modules are idempotent: a second run is a no-op (verified by `doctor`)
- [ ] Package sets clearly separated into `base`, `desktop`, `aur` lists
- [ ] Self-update runs at most once per interval on shell open, never blocking the prompt
- [ ] `shellcheck` + `shfmt -d` clean; bats tests pass for lib functions
- [ ] Global flags honored: `--dry-run --verbose --quiet --yes --no-color`

## Architecture (target layout)
```
archinit/
├── install.sh                  # bootstrap: git + clone/update + shell hook
├── bin/archinit                # CLI entrypoint (dispatcher)
├── VERSION
├── lib/                        # sourced libs, no side effects on source
│   ├── core.sh  log.sh  ui.sh  os.sh  pkg.sh  service.sh  fs.sh  config.sh  state.sh  update.sh
│   ├── snapshot.sh  git.sh  dotfiles.sh
├── cmd/                        # one file per verb
│   ├── install.sh update.sh doctor.sh tui.sh list.sh version.sh snapshot.sh restore.sh uninstall.sh config.sh
├── modules/                    # idempotent units, numbered
│   ├── 00-base/ 10-aur-helper/ 20-services/ 30-desktop/ 35-git/ 40-dev/  (each: module.sh)
├── config/
│   ├── defaults.conf
│   └── packages/
│       ├── base.txt            # official base packages
│       ├── desktop.txt         # official desktop/GUI packages
│       └── aur.txt             # AUR packages
├── shell/archinit.sh           # rc hook: PATH + auto-update-on-login
└── tests/{bats/, lint.sh}
```

## Runtime state vs repo (XDG)
The git clone `~/.archinit` is **read-only-ish**: only shipped defaults live there. All machine-derived/generated state lives under XDG dirs so the repo never gets cluttered:
```
$XDG_STATE_HOME/archinit/        (default ~/.local/state/archinit/)
├── .last_update                 # self-update throttle timestamp
├── .state/                      # module completion markers
├── logs/                        # per-run logs (<ISO-ts>.log)
└── snapshots/
    ├── 2026-06-09T14-30-00/
    │   ├── native.txt           # pacman -Qqen  (official explicit)
    │   └── foreign.txt          # pacman -Qqem  (AUR/local explicit)
    └── latest -> 2026-06-09T14-30-00   # symlink to most recent
```
Rationale: a package snapshot is machine-derived and regenerable → XDG_STATE (not XDG_CONFIG). Matches dman's `~/.local/state/dman/snapshots` convention. User config overrides still live in `~/.archinit/config.local` (or `$XDG_CONFIG_HOME/archinit/config.local`).

### Portable snapshots via dman (closing the loop)
The user can track `~/.local/state/archinit` (or just the `latest` snapshot's `native.txt`/`foreign.txt`) inside their **dman dotfiles repo** (`dot_local/state/archinit/...`). Then on a new machine:
1. `dman apply` restores the snapshot files into `~/.local/state/archinit`.
2. `archinit install`/`update` reads the restored `latest` snapshot and ensures those packages are installed too — making the package set portable through dman with no separate sync mechanism.

This makes the latest snapshot a **fourth, machine-contributed package source** merged with the curated `base`/`desktop`/`aur` lists (de-duplicated; `native.txt`→pacman, `foreign.txt`→yay; `--needed` keeps it idempotent so curated packages are no-ops). Gated by config `INSTALL_SNAPSHOT_PACKAGES` (default `true`) so it can be disabled. Note: tracking the timestamped history would bloat the dotfiles repo — recommend tracking only `latest/native.txt` and `latest/foreign.txt`.

## Module contract (every `module.sh` implements)
```bash
module_name()     { echo "base"; }            # stable id
module_class()    { echo "base"; }            # base|desktop|aur|service|dev
module_describe() { echo "Core system packages"; }
module_requires() { echo ""; }                # space-separated module ids this depends on (optional)
module_check()    { ... ; }                   # 0 = already satisfied (idempotency gate)
module_install()  { ... ; }                   # do the work, must be safe to re-run
```
Dispatcher resolves `module_requires` into a topological order (deps first), then loops; `install` skips when `module_check` returns 0 unless `--force`. Numeric directory prefixes provide a stable default order; `module_requires` handles real dependencies (e.g. any aur-class or `40-dev` requires `aur-helper`).

## Package class semantics
| Class   | Source           | Installer                         | List file              |
|---------|------------------|-----------------------------------|------------------------|
| base    | official repos   | `pacman -S --needed`              | `config/packages/base.txt` |
| desktop | official repos   | `pacman -S --needed`              | `config/packages/desktop.txt` |
| aur     | AUR              | `yay -S --needed` (helper req.)   | `config/packages/aur.txt` |

List files: one package per line, `#` comments and blank lines ignored.

---

## Phases

### Phase 1: Core libraries & conventions
**Status**: pending

#### 1.1 core.sh — strict mode, guards, traps
- [ ] **Task**: Create sourcing-safe core with strict mode and error trap
- **File(s)**: `lib/core.sh`
- **Details**: `set -euo pipefail`; safe `IFS`; double-source guard (`[[ -n ${_ARCHINIT_CORE:-} ]] && return; _ARCHINIT_CORE=1`); **Bash version guard** (`((BASH_VERSINFO[0] >= 4)) || die "bash >= 4 required"`); define `ARCHINIT_HOME` (default `${ARCHINIT_HOME:-$HOME/.archinit}`); `die()`, `require_cmd()`, `is_root()`, `as_root()` (wraps `sudo` only when not root); **`sudo_keepalive()`** (`sudo -v` then a backgrounded refresh loop, killed via EXIT trap) so long installs don't prompt mid-run; never run `makepkg` as root. `ERR` trap printing failing command + line via `BASH_COMMAND`/`LINENO`. Provide `DRY_RUN`, `ASSUME_YES`, `VERBOSE`, `QUIET`, `NO_COLOR` globals defaulting to empty. `run()` helper that echoes (dry-run) or executes a command.
- **Verify**: `bash -n lib/core.sh`; `shellcheck lib/core.sh`; on bash 3 it dies with a clear message

#### 1.2 log.sh — leveled logging + color + file log
- [ ] **Task**: Logging helpers respecting `--quiet/--verbose/--no-color`, with per-run file log
- **File(s)**: `lib/log.sh`
- **Details**: `log_info/log_warn/log_error/log_debug/log_ok`. Colors via tput, disabled when `NO_COLOR` set or stdout not a tty. `log_debug` only when `VERBOSE`. Errors/warns go to stderr. **File logging**: `log_init` opens `$ARCHINIT_STATE/logs/<ISO-ts>.log` (created on first mutating command, e.g. by `install`/`update`/`restore`); every `log_*` also appends an uncolored, timestamped line there. Symlink `logs/latest.log` to the current run. `archinit doctor`/`--help` (read-only) need not open a log.
- **Verify**: `shellcheck`; `VERBOSE=1 ... log_debug` prints; after an install a `logs/<ts>.log` exists with the run output

#### 1.3 os.sh — environment detection
- [ ] **Task**: Arch + tool detection helpers
- **File(s)**: `lib/os.sh`
- **Details**: `assert_arch()` (check `/etc/os-release` ID=arch, else die); `has_cmd()`; `pkg_is_installed()` via `pacman -Qi`; `aur_helper()` returns first of `yay`/`paru` or empty; `has_aur_helper()`.
- **Verify**: `shellcheck`; `assert_arch` succeeds on Arch test container

#### 1.4 pkg.sh — idempotent package install (3 classes)
- [ ] **Task**: Class-aware install functions reading list files
- **File(s)**: `lib/pkg.sh`
- **Details**:
  - `pkg_read_list FILE` → prints cleaned package names (strip comments/blanks).
  - `pkg_install_official PKG...` → `as_root pacman -S --needed --noconfirm` (skip already-installed via `--needed`; honor DRY_RUN via `run`).
  - `pkg_install_aur PKG...` → require `has_aur_helper` (else die with hint to run `aur-helper` module); `"$(aur_helper)" -S --needed --noconfirm`.
  - `pkg_install_list base|desktop|aur` → resolve `config/packages/<class>.txt`, dispatch to official/aur installer accordingly.
  - **Failure policy**: install package-by-package (or batch then fall back per-package on error); collect failures into an array, continue the rest, and print a summary at the end (`N installed, M failed: <names>`). A single bad AUR package must not abort the whole run. Return non-zero if any failed so callers/`doctor` can react.
- **Verify**: `shellcheck`; `--dry-run` prints the exact pacman/yay commands without executing; a simulated failing package is reported in the summary, others still install

#### 1.5 service.sh — idempotent systemd
- [ ] **Task**: Enable/start units idempotently (system + user)
- **File(s)**: `lib/service.sh`
- **Details**: `service_enable UNIT` (system, `--now`, skip if `is-enabled`); `service_enable_user UNIT`; guard with `systemctl is-enabled`/`is-active`; honor DRY_RUN.
- **Verify**: `shellcheck`; second call is a no-op

#### 1.6 fs.sh — safe filesystem ops (dotfiles)
- [ ] **Task**: Backup-aware symlink/copy
- **File(s)**: `lib/fs.sh`
- **Details**: `backup PATH` (move existing non-symlink to `*.archinit.bak.<ts>`); `symlink SRC DST` (no-op if already correct link); `ensure_dir DIR`. Used later by dev/dotfiles module (dman).
- **Verify**: `shellcheck`; re-running `symlink` does not re-backup

#### 1.7 state.sh — completion markers (no jq dependency)
- [ ] **Task**: Track completed modules with marker files
- **File(s)**: `lib/state.sh`
- **Details**: State dir `$ARCHINIT_STATE/.state` where `ARCHINIT_STATE=${XDG_STATE_HOME:-$HOME/.local/state}/archinit` (defined in `core.sh`); `state_mark NAME`, `state_done NAME` (test marker), `state_clear NAME`. Used by `doctor`/`list` for drift reporting (informational; `module_check` remains source of truth).
- **Verify**: `shellcheck`; mark then `state_done` returns 0

#### 1.8 ui.sh — TUI abstraction (gum → whiptail fallback)
- [ ] **Task**: Single interface over TUI backends
- **File(s)**: `lib/ui.sh`
- **Details**: Detect backend: prefer `gum`, fallback `whiptail`, then `dialog`, else plain-text prompts. Expose `ui_confirm MSG`, `ui_choose_multi TITLE item1 item2...` (returns selected ids), `ui_menu`. When `ASSUME_YES`, `ui_confirm` returns 0 without prompting. Commands must never call gum/whiptail directly.
- **Verify**: `shellcheck`; works with each backend or none (text fallback)

#### 1.9 snapshot.sh — package snapshot/restore (XDG state)
- [ ] **Task**: Capture and restore explicit package lists, split by class
- **File(s)**: `lib/snapshot.sh`
- **Details**: Snapshot dir `$ARCHINIT_STATE/snapshots` (XDG_STATE). Functions:
  - `snapshot_create` → make `snapshots/<ISO-ts>/` with `native.txt` (`pacman -Qqen`) and `foreign.txt` (`pacman -Qqem`); update `latest` symlink atomically (`ln -sfn`). Honor DRY_RUN.
  - `snapshot_list` → list snapshot dirs newest-first, marking `latest`.
  - `snapshot_latest` → resolve `latest` target (empty if none).
  - `snapshot_exists` → 0 if any snapshot present (used by doctor/list).
  - `snapshot_restore [NAME]` → from given/`latest`: `pkg_install_official $(<native.txt)` and `pkg_install_aur $(<foreign.txt)` via `lib/pkg.sh` (idempotent `--needed`). Require AUR helper for foreign; die with hint if missing.
  - `snapshot_native_packages` / `snapshot_foreign_packages` → print cleaned package names from `latest` (empty if no snapshot). Used by `install`/`update` to merge snapshot packages with curated lists.
- **Verify**: `shellcheck`; `snapshot_create` writes two files + `latest`; re-running `snapshot_restore` is a no-op; `--dry-run` writes/installs nothing

**Phase verify**: `bash tests/lint.sh` (shellcheck+shfmt) clean for all `lib/*.sh`

---

### Phase 2: Config & package lists
**Status**: pending

#### 2.1 defaults.conf
- [ ] **Task**: Default settings, overridable by `~/.archinit/config.local`
- **File(s)**: `config/defaults.conf`
- **Details**: Keys: `UPDATE_INTERVAL_HOURS=24`, `AUR_HELPER=yay`, `DEFAULT_MODULES="base aur-helper services"`, `DOTFILES_MANAGER=dman`, `DOTFILES_REPO=""`, `DOTFILES_PROFILE=default`, `INSTALL_SNAPSHOT_PACKAGES=true`, `DISPLAY_MANAGER=sddm`, `GIT_USER_NAME=""`, `GIT_USER_EMAIL=""`, `GIT_AUTH_METHOD=ssh` (`ssh|token|skip`), `SETUP_GH_CLI=true`, `GIT_REMOTE`, branch. `config.sh` loads defaults then sources `config.local` if present.
- **Verify**: `shellcheck`; missing local file does not error

#### 2.2 config.sh loader
- [ ] **Task**: Load/merge config
- **File(s)**: `lib/config.sh`
- **Details**: Source defaults.conf, then `$ARCHINIT_HOME/config.local`; export resolved vars. Provide `config_get KEY`.
- **Verify**: `shellcheck`; overridden value wins

#### 2.3 base.txt (official base packages)
- [ ] **Task**: Seed core CLI/system packages
- **File(s)**: `config/packages/base.txt`
- **Details**: e.g. `base-devel git curl wget zsh neovim ripgrep fd fzf bat eza unzip man-db openssh reflector`. Commented header explaining format. (Editable by user.)
- **Verify**: `pkg_read_list` returns non-empty, no comment lines

#### 2.4 desktop.txt (official desktop packages — Hyprland stack)
- [ ] **Task**: Seed Hyprland Wayland desktop packages
- **File(s)**: `config/packages/desktop.txt`
- **Details**: e.g. `hyprland xdg-desktop-portal-hyprland wayland qt5-wayland qt6-wayland waybar wofi mako swaync hyprlock hypridle swaybg grim slurp wl-clipboard kitty thunar polkit-gnome network-manager-applet brightnessctl pavucontrol ttf-jetbrains-mono-nerd noto-fonts noto-fonts-emoji`. Display/login: `sddm` (enabled in services module) or TTY+`uwsm`/`Hyprland` launch — pick `sddm`. Note audio assumed installed post-archinstall; keep entries idempotent (`--needed`).
- **Verify**: `pkg_read_list desktop` parses cleanly

#### 2.5 aur.txt (AUR packages — via yay)
- [ ] **Task**: Seed AUR-only packages
- **File(s)**: `config/packages/aur.txt`
- **Details**: e.g. `dman visual-studio-code-bin brave-bin spotify hyprshot wlogout`. `dman` is published on the AUR (`yay -S dman`). Header notes `yay` required.
- **Verify**: `pkg_read_list aur` parses cleanly

---

### Phase 3: Modules
**Status**: pending

#### 3.1 00-base
- [ ] **Task**: Install base class
- **File(s)**: `modules/00-base/module.sh`
- **Details**: `module_class=base`; `module_check` = all base packages installed (loop `pkg_is_installed`); `module_install` = `pkg_install_list base`.
- **Verify**: install once, `module_check` returns 0 on re-run

#### 3.2 10-aur-helper
- [ ] **Task**: Bootstrap yay from source (no AUR helper yet)
- **File(s)**: `modules/10-aur-helper/module.sh`
- **Details**: `module_check` = `has_aur_helper`; `module_install` = ensure `base-devel git`, clone `https://aur.archlinux.org/yay.git` to temp, `makepkg -si --noconfirm`, cleanup. Must precede any aur-class module.
- **Verify**: `command -v yay` after run; re-run is no-op

#### 3.3 20-services
- [ ] **Task**: Enable common services idempotently
- **File(s)**: `modules/20-services/module.sh`
- **Details**: `service_enable NetworkManager`, `sshd` (optional), `service_enable_user pipewire wireplumber` as applicable. `module_check` = all target units enabled.
- **Verify**: second run no-op; `systemctl is-enabled` green

#### 3.4 30-desktop (Hyprland)
- [ ] **Task**: Install Hyprland desktop class + display manager
- **File(s)**: `modules/30-desktop/module.sh`
- **Details**: `module_class=desktop`; `module_install` = `pkg_install_list desktop`, install `sddm`, then `service_enable sddm`. `module_check` = desktop packages present AND `sddm` enabled.
- **Verify**: idempotent re-run

#### 3.5 35-git (git + auth + gh cli)
- [ ] **Task**: Interactively assist git/GitHub auth setup (all optional)
- **File(s)**: `modules/35-git/module.sh`, `lib/git.sh`
- **Details**: `module_requires "base"`. Uses `ui_menu`/`ui_confirm` from `lib/ui.sh`. Top-level choice:
  - **Setup Git** → prompt for `user.name` and `user.email`, write via `git config --global` (idempotent: only set if unset or `--force`). Then auth method submenu:
    - **HTTPS with token** → prompt for GitHub username + PAT (read with `read -rs`, never echoed/logged); store credentials via `git config --global credential.helper store` writing to `~/.git-credentials` (chmod 600) **or** the token to `$ARCHINIT_STATE/secrets.local` (chmod 600) — gitignored, used to build authenticated remote URLs for dman.
    - **Use SSH key** → if no key, `ssh-keygen -t ed25519 -C "$email"` (idempotent: skip if key exists); start agent + `ssh-add`; print the public key and prompt the user to add it as a GitHub **deploy key**/account key; offer `ssh -T git@github.com` test.
  - **Skip Git setup** → no-op.
  - **gh cli (optional)**: offer to install `github-cli` and run `gh auth login` (skippable). `module_check` = `gh auth status` succeeds (when chosen) or git identity configured.
- **Details (`lib/git.sh`)**: `git_is_configured`, `git_set_identity NAME EMAIL`, `git_setup_https_token`, `git_setup_ssh_key`, `gh_setup`. All idempotent; secrets read with `read -rs`, never passed on the command line or logged; honor DRY_RUN.
- **Verify**: re-run is a no-op when identity/auth already present; token/keys never appear in logs or `--verbose` output; `--dry-run` prompts nothing destructive

#### 3.6 40-dev (dotfiles via dman)
- [ ] **Task**: AUR dev tools + dotfile application via dman
- **File(s)**: `modules/40-dev/module.sh`
- **Details**: `module_requires "aur-helper git"`; `pkg_install_list aur` (includes `dman`); then apply dotfiles through the dotfiles abstraction in `lib/dotfiles.sh` (default backend `dman`). `module_check` = `dman` present and config initialized (`~/.config/dman/dman.json` exists). Reuses auth from `35-git`: **prefer SSH deploy key or `gh auth`** over a stored token for the dotfiles repo URL; if only a token exists, build the authenticated HTTPS URL from `secrets.local`. Secrets never logged.
- **Verify**: idempotent; `dman apply` re-run converges (copies only changed files); no secret echoed

#### 3.7 lib/dotfiles.sh (dotfiles abstraction)
- [ ] **Task**: Swappable dotfiles manager (default dman)
- **File(s)**: `lib/dotfiles.sh`
- **Details**: Read `DOTFILES_MANAGER` (default `dman`), `DOTFILES_REPO`, `DOTFILES_PROFILE` from config. `dotfiles_init REPO` → `dman init REPO` (only if `~/.config/dman/dman.json` absent — idempotency gate); `dotfiles_apply` → `dman apply --profile "$DOTFILES_PROFILE"` (honor DRY_RUN via `--dry-run`); `chezmoi`/`stow` backends stubbed for swap. Note: `dman` is copy-based with pre-apply snapshots, so re-apply is safe.
- **Verify**: `shellcheck`; re-running `dotfiles_apply` converges; `--dry-run` writes nothing

---

### Phase 4: CLI dispatcher & commands
**Status**: pending

#### 4.1 bin/archinit — entrypoint + arg parser
- [ ] **Task**: Parse global flags, route to `cmd/<verb>.sh`
- **File(s)**: `bin/archinit`
- **Details**: Resolve `ARCHINIT_HOME` from script path; source `lib/core.sh log.sh config.sh` + needed libs. Parse global flags (`--dry-run --verbose --quiet --yes --no-color -h/--help`) into core globals. First non-flag arg = verb; default verb (no args) = `tui`. Unknown verb → help + exit 1. Source `cmd/$verb.sh` and call `cmd_<verb> "$@"`. **Per-subcommand help**: `archinit <verb> --help` calls an optional `cmd_<verb>_help` (each cmd file defines one) and exits 0; top-level `archinit help` lists all verbs.
- **Verify**: `bin/archinit --help`; `bin/archinit version`; `bin/archinit install --help` prints install usage; unknown verb errors

#### 4.2 cmd/version.sh
- [ ] **Task**: Print VERSION
- **File(s)**: `cmd/version.sh`, `VERSION`
- **Details**: Read `VERSION` file; print with git short sha if available.
- **Verify**: `archinit version` prints semver

#### 4.3 cmd/list.sh
- [ ] **Task**: List modules with class + status
- **File(s)**: `cmd/list.sh`
- **Details**: Iterate `modules/*/module.sh` in numeric order, source in subshell, print `name | class | describe | [ok|pending]` using `module_check`.
- **Verify**: `archinit list` shows all modules

#### 4.4 cmd/install.sh
- [ ] **Task**: Run modules idempotently (all or named)
- **File(s)**: `cmd/install.sh`
- **Details**: Args = module names (default `config_get DEFAULT_MODULES` or all). **Resolve `module_requires` into a topological order (deps first)** before running; detect cycles and die. For each module in resolved order: source in subshell, `module_check` → skip unless `--force`, else `module_install`; `state_mark` on success. Respect `--dry-run`. When `INSTALL_SNAPSHOT_PACKAGES=true` and a `latest` snapshot exists, after modules also ensure snapshot packages: `pkg_install_official $(snapshot_native_packages)` + `pkg_install_aur $(snapshot_foreign_packages)` (merged/de-duped with curated lists, idempotent via `--needed`). Skippable with `--no-snapshot`. Refactor the core loop into `run_modules NAMES...` (reused by `tui`).
- **Verify**: `archinit install base` works; `archinit install dev` auto-pulls `aur-helper`+`git` first; re-run skips; snapshot packages restored when present; `--dry-run` executes nothing

#### 4.5 cmd/doctor.sh
- [ ] **Task**: Read-only health/drift report
- **File(s)**: `cmd/doctor.sh`
- **Details**: `assert_arch`; check git repo health, AUR helper presence, each `module_check`, service states, and `snapshot_exists` (report latest snapshot timestamp or "no snapshot yet"). Never mutate. Exit non-zero if any check fails (useful in CI/hooks).
- **Verify**: `archinit doctor` lists pass/fail incl. snapshot status; exit code reflects state

#### 4.6 cmd/update.sh
- [ ] **Task**: Self-update + optional re-run
- **File(s)**: `cmd/update.sh`, `lib/update.sh`
- **Details**: `update_self()` in `lib/update.sh`: `git -C $ARCHINIT_HOME fetch`, fast-forward only; warn (don't clobber) on local changes; touch `.last_update`. `cmd_update` calls it then optionally `pacman -Syu`/`yay -Syu`, re-runs pending modules, and (when `INSTALL_SNAPSHOT_PACKAGES=true`) ensures `latest` snapshot packages are installed (idempotent `--needed`) — so packages added on another machine and synced via dman get picked up. Respect `--dry-run`.
- **Verify**: dirty tree → warning, no clobber; clean → ff pull

#### 4.7 cmd/tui.sh
- [ ] **Task**: Interactive module selector
- **File(s)**: `cmd/tui.sh`
- **Details**: Use `ui_choose_multi` to present modules (grouped by class), preselect pending ones, then call install logic for chosen modules (reuse `cmd_install` internals — refactor shared runner into a `lib` function `run_modules NAMES...` to avoid duplication).
- **Verify**: selecting items installs them; cancel exits cleanly

#### 4.8 cmd/snapshot.sh
- [ ] **Task**: Capture installed explicit packages to XDG state
- **File(s)**: `cmd/snapshot.sh`
- **Details**: `cmd_snapshot` subverbs: default/`create` → `snapshot_create` (writes `native.txt`+`foreign.txt`, updates `latest`); `list` → `snapshot_list`; `show [NAME]` → print contents of given/`latest`. Pure capture, never writes into the repo. Respect `--dry-run`.
- **Verify**: `archinit snapshot` creates a timestamped snapshot under `~/.local/state/archinit/snapshots`; `archinit snapshot list` shows it; repo working tree stays clean

#### 4.9 cmd/restore.sh
- [ ] **Task**: Reinstall packages from a snapshot
- **File(s)**: `cmd/restore.sh`
- **Details**: `cmd_restore [NAME]` → `snapshot_restore` from given snapshot or `latest`. Confirm via `ui_confirm` unless `--yes`. Native via `pacman -S --needed`, foreign via `yay -S --needed` (idempotent). Die with hint if no snapshot exists or AUR helper missing. Respect `--dry-run`.
- **Verify**: `archinit restore --dry-run` lists packages without installing; real run is idempotent on re-run

#### 4.10 cmd/config.sh
- [ ] **Task**: View/set config keys in `config.local`
- **File(s)**: `cmd/config.sh`
- **Details**: `archinit config` (list resolved keys), `archinit config <key>` (print), `archinit config <key> <value>` (write to `$ARCHINIT_HOME/config.local`, creating it), `archinit config --unset <key>`. Validate key against known defaults; never touch shipped `defaults.conf`. Mirrors dman's `config` ergonomics.
- **Verify**: set then get round-trips; `defaults.conf` untouched; unknown key warns

#### 4.11 cmd/uninstall.sh
- [ ] **Task**: Remove archinit (keep installed packages)
- **File(s)**: `cmd/uninstall.sh`
- **Details**: Confirm via `ui_confirm` unless `--yes`. Remove the `source ".../shell/archinit.sh"` line from `~/.zshrc`/`~/.bashrc` (idempotent), then `rm -rf ~/.archinit`. Leave installed packages and `$XDG_STATE_HOME/archinit` snapshots by default; `--purge` also removes XDG state. Print what was/wasn't removed. Respect `--dry-run`.
- **Verify**: `archinit uninstall --dry-run` lists actions; real run removes rc line + clone, packages remain

**Phase verify**: `shellcheck bin/archinit cmd/*.sh`; manual smoke of each verb with `--dry-run`

---

### Phase 5: Bootstrap & shell hook
**Status**: pending

#### 5.1 install.sh (bootstrap)
- [ ] **Task**: Idempotent installer
- **File(s)**: `install.sh`
- **Details**: Wrap the whole body in `main() { ...; }` and call `main "$@"` at the very end (so a truncated `curl | bash` download can't run a half-script). `set -euo pipefail`; detect Arch; ensure `git` (`pacman -S --needed --noconfirm git`); if `~/.archinit/.git` exists → `git pull --ff-only`, else `git clone $REPO ~/.archinit`; `chmod +x ~/.archinit/bin/archinit` (absolute path, post-clone); add hook line `source "$HOME/.archinit/shell/archinit.sh"` to `~/.zshrc`/`~/.bashrc` only if absent; print next steps; optionally exec TUI on first run. Re-running must be safe.
- **Verify**: run twice → second is update, no duplicate rc lines; partial download (truncated before `main`) does nothing

#### 5.2 shell/archinit.sh (rc hook)
- [ ] **Task**: PATH + throttled auto-update on shell open
- **File(s)**: `shell/archinit.sh`
- **Details**: Prepend `$HOME/.archinit/bin` to PATH (guard duplicates). Auto-update: if now − mtime(`.last_update`) > `UPDATE_INTERVAL_HOURS`, run `archinit update` in background (`&` + `disown`), redirect output to a log, never block prompt. Guard so it does nothing in non-interactive shells.
- **Verify**: opening new shell sets PATH; update throttled to once/interval; prompt not blocked

---

### Phase 6: Quality gates & docs
**Status**: pending

#### 6.1 tests/lint.sh
- [ ] **Task**: Lint runner
- **File(s)**: `tests/lint.sh`
- **Details**: Run `shellcheck` over `bin/ lib/ cmd/ modules/ install.sh shell/`; run `shfmt -d -i 2 -ci`. Non-zero on issues.
- **Verify**: `bash tests/lint.sh` clean

#### 6.2 bats unit tests for libs
- [ ] **Task**: Test pure functions
- **File(s)**: `tests/bats/pkg.bats`, `tests/bats/fs.bats`, `tests/bats/core.bats`
- **Details**: Test `pkg_read_list` (comment/blank stripping), `symlink`/`backup`, `run` dry-run echoes without executing, config override precedence. Mock `pacman`/`systemctl` via PATH shims.
- **Verify**: `bats tests/bats` passes

#### 6.3 README update
- [ ] **Task**: Document install, CLI, modules, package classes
- **File(s)**: `README.md`
- **Details**: Update with new architecture, command reference, how to edit `config/packages/{base,desktop,aur}.txt`, the `snapshot`/`restore` workflow + XDG state location, and self-update behavior.
- **Verify**: instructions match actual commands

#### 6.4 CI (optional)
- [ ] **Task**: GitHub Actions lint + bats + Arch smoke
- **File(s)**: `.github/workflows/ci.yml`
- **Details**: Ubuntu runner: install shellcheck/shfmt/bats; run `tests/lint.sh` and `bats`. Add an **Arch container job** (`container: archlinux:latest`) that installs deps and runs `archinit install --dry-run` for each module + `archinit doctor` to smoke real pacman/systemctl detection without reinstalling a machine.
- **Verify**: workflow green; Arch job exercises dry-run modules

---

## Verification (global)
- [ ] `bash -n` on every script (no syntax errors)
- [ ] `shellcheck` clean across `bin/ lib/ cmd/ modules/ install.sh shell/`
- [ ] `shfmt -d -i 2 -ci` clean
- [ ] `bats tests/bats` passes
- [ ] `archinit --help|version|list|doctor` work; `doctor` exit code reflects state
- [ ] `archinit install <module> --dry-run` prints commands, mutates nothing
- [ ] `archinit snapshot` writes to `~/.local/state/archinit/snapshots` and leaves the repo clean
- [ ] `archinit restore --dry-run` lists native+foreign packages without installing
- [ ] `archinit config`/`uninstall` and `archinit <verb> --help` behave as specified
- [ ] git module: each auth path is idempotent and leaks no secret to logs/`--verbose`
- [ ] A simulated failing package is summarized; the rest still install
- [ ] Re-running any module is a no-op (idempotency)
- [ ] `install.sh` run twice → second is a clean update, no duplicate rc lines
- [ ] New shell adds bin to PATH and throttles self-update

## Decisions
| Decision | Choice | Rationale |
|----------|--------|-----------|
| TUI backend | `gum` preferred, `whiptail`→`dialog`→text fallback | Modern UX without hard dependency; whiptail ships widely |
| State tracking | `.state/` marker files | No `jq` dependency; `module_check` stays source of truth |
| Runtime state location | `$XDG_STATE_HOME/archinit` (`~/.local/state/archinit`) | Keeps generated state (snapshots, markers, update ts) out of the git clone |
| Package snapshots | `pacman -Qqen`+`-Qqem` split into `native.txt`/`foreign.txt`, timestamped + `latest` symlink | Round-trips to official vs AUR installers; regenerable → state not config; mirrors dman convention |
| Portable snapshots | track `~/.local/state/archinit` in dman; `install`/`update` merge `latest` snapshot packages | dman syncs the list across machines; archinit picks them up automatically (gated by `INSTALL_SNAPSHOT_PACKAGES`) — no separate sync needed |
| Package classes | base / desktop / aur in separate list files | Clear separation; official vs AUR installer differs; user-editable |
| Module format | numbered dirs with `module.sh` contract | Deterministic order, generic dispatcher loop |
| Module dependencies | `module_requires` + topological resolve | Scales beyond numeric ordering; `dev` auto-pulls `aur-helper`+`git` |
| Run logging | per-run file under `$XDG_STATE/archinit/logs` + `latest.log` | Debuggable on a headless fresh box; colorless timestamped lines |
| Package failure policy | collect failures, continue, summarize, non-zero exit | One bad AUR package mustn't abort a 40-package run |
| Git auth | menu: SSH key / HTTPS token / skip; optional `gh auth` | Prefer SSH deploy key or `gh` over storing a PAT; secrets via `read -rs`, chmod 600, never logged |
| Self-update | git ff-only, throttled, backgrounded | oh-my-zsh-style, never clobbers local edits or blocks prompt |
| Strict mode | `set -euo pipefail` + ERR trap | Robustness; fail fast with location |
| AUR helper | `yay` | Locked in per user choice |
| AUR bootstrap | build `yay` from source in `10-aur-helper` | Fresh Arch has no AUR helper |
| Desktop | Hyprland (Wayland) + `sddm` | Locked in per user choice |
| Dotfiles | `dman` (default), pluggable via `DOTFILES_MANAGER` | User's own copy-based manager (AUR `dman`); snapshots make re-apply safe; chezmoi/stow swappable |
| Privilege | `as_root` wraps sudo only when needed | Avoid running whole script as root |

## Rollback
- Tool lives entirely in `~/.archinit` → `rm -rf ~/.archinit` removes it.
- Remove the `source ".../shell/archinit.sh"` line from `~/.zshrc`/`~/.bashrc`.
- Dotfile changes are backed up as `*.archinit.bak.<ts>` by `fs.sh backup`; restore from those.
- Installed packages remain (intentional); list them via `archinit list` and remove manually if desired.
- Dotfiles applied by dman: pre-apply snapshots are kept under `~/.local/state/dman/snapshots` (restore via `dman snapshot`); `dman purge` removes dman config and the local clone.

## Resolved decisions
1. AUR helper: **yay**.
2. Desktop: **Hyprland** (Wayland) with **sddm** display manager.
3. Dotfiles: **dman** (`github.com/alexjoedt/dman`) as default backend in `40-dev`, behind `lib/dotfiles.sh` (`DOTFILES_MANAGER` configurable).
