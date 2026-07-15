# Plan: Desktop Profiles (hyprland / niri / kde)

Make the desktop layer selectable via named **profiles**. Today,
`modules/30-desktop/module.sh` and `config/packages/desktop.txt` are hardcoded to
Hyprland. We introduce `config/profiles/<name>/` bundles, a `DESKTOP_PROFILE`
config key, an `archinit profile` command, and a `--profile` install override —
each profile controlling its desktop packages, display manager, AUR packages, and
dotfiles profile.

## New structure

```
config/profiles/<name>/
  profile.conf   # PROFILE_DESCRIBE, DISPLAY_MANAGER, DOTFILES_PROFILE (sourced bash overlay)
  packages.txt   # official desktop packages
  aur.txt        # profile-specific AUR packages (optional)
```

## Decisions

- A **profile** controls: desktop package set, display manager, profile-specific
  AUR packages, and dotfiles profile.
- Selection mechanisms: `DESKTOP_PROFILE` config key + `archinit profile` command
  + `--profile` install flag + interactive prompt during TUI/install when unset.
- Populate **hyprland** fully now; scaffold **niri** and **kde** with starter lists.
- Generic AUR tools (`dman`, `vscode`, `brave`, `spotify`) stay in
  `config/packages/aur.txt` — they are dev/general, not desktop-specific.
- `--profile` uses a dedicated `ARCHINIT_PROFILE_OVERRIDE` env var to survive
  `config_load` (which would otherwise clobber a plain `DESKTOP_PROFILE` env var).
- Excluded for now: profiles declaring extra modules/services.

## Phase 1 — Profile foundation

1. Add `DESKTOP_PROFILE=hyprland` to `config/defaults.conf` under the
   Display/desktop section.
2. Create `lib/profile.sh` (follows lib conventions: double-source guard,
   `profile_` prefix, no side effects on source) with:
   - `profile_active` — checks `ARCHINIT_PROFILE_OVERRIDE` env first, else
     `config_get DESKTOP_PROFILE`, default `hyprland`.
   - `profile_dir`, `profile_exists`, `profile_list`.
   - `profile_load` — sources the profile's `profile.conf` overlay.
   - `profile_describe`, `profile_require`.
   - `profile_install_packages` — reuses `pkg_read_list` +
     `pkg_install_official` / `pkg_install_aur`.
   - `profile_ensure_selected` — prompts via `ui_menu` when not set in
     `config.local` and a TTY is present (never under `--yes` / `--dry-run`).

## Phase 2 — Make desktop profile-aware (depends on Phase 1)

3. Rewrite `modules/30-desktop/module.sh`: resolve the active profile; in
   `module_check` / `module_install` install the profile's `packages.txt`
   (+ `aur.txt` if an AUR helper exists), enable the profile's `DISPLAY_MANAGER`,
   and set `DOTFILES_PROFILE`. Keeps `assert_arch` and idempotency rules.
4. In `lib/install.sh` `run_modules`, add `ARCHINIT_PROFILE_OVERRIDE` to the
   exported env block of the `module_install` subshell so the `--profile` flag
   reaches the module.

## Phase 3 — CLI surface (depends on Phase 1)

5. Create `cmd/profile.sh` with subcommands:
   - `list` — mark active + show package counts.
   - `show [name]` — display manager, dotfiles profile, counts.
   - `set <name>` — validate + `config_set DESKTOP_PROFILE`.
   - plus `cmd_profile_help`. Auto-discovered by the dispatcher.
6. Update `cmd/install.sh`: parse `--profile <name>` / `--profile=name`, validate
   via `profile_require`, export `ARCHINIT_PROFILE_OVERRIDE`, call
   `profile_ensure_selected` when `desktop` is in the module list; update help.
7. Update `cmd/tui.sh` to call `profile_ensure_selected` when `desktop` is selected.
8. Add `profile` to the top-level help in `bin/archinit`.

## Phase 4 — Profile content + migration (parallel with Phase 3)

9. Create `config/profiles/hyprland/` — migrate `config/packages/desktop.txt` into
   `packages.txt`, move `hyprshot` / `wlogout` from `config/packages/aur.txt` into
   the profile's `aur.txt`, write `profile.conf`
   (`DISPLAY_MANAGER=sddm`, `DOTFILES_PROFILE=hyprland`).
10. Scaffold `config/profiles/niri/` and `config/profiles/kde/` with `profile.conf`
    + minimal sensible starter `packages.txt` / `aur.txt`.
11. Remove `config/packages/desktop.txt` (replaced by the hyprland profile).

## Phase 5 — Docs & tests

12. Update `README.md` (tree, package-class table, profiles section) and the
    Package Lists section of `.github/instructions/archinit.instructions.md`.
13. Add `tests/bats/profile.bats` (default active = hyprland, `profile_exists`,
    `profile_list`); check `tests/bats/pkg.bats` for `desktop.txt` references.

## Verification

1. `bash -n` on all changed/new scripts.
2. `bash tests/lint.sh` (shellcheck + shfmt) passes.
3. `bats tests/bats/` passes.
4. `archinit profile list`, `archinit profile show hyprland`,
   `archinit profile set niri`.
5. `archinit install desktop --profile niri --dry-run` resolves the niri profile's
   packages / display manager.
6. `archinit config DESKTOP_PROFILE` reflects the set value.

## Open considerations

1. niri/kde package lists — ship **minimal sensible starters** (niri, waybar, etc.;
   plasma-meta, etc.) vs. **commented placeholders**. Recommendation: minimal
   sensible starters so they are usable immediately.
2. Prompt trigger — only prompt when `DESKTOP_PROFILE` is absent from `config.local`
   and a TTY exists (never under `--yes` / `--dry-run`). Recommendation: as
   described.
