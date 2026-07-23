---
title: Overview
description: Machine facts, baseline checklist, script map, and wiki map for this Arch + Hyprland laptop.
outline: deep
---

# Personal Arch + Hyprland wiki

Operations notes for this laptop. Use them after a break, bad update, or
migration so you do not re-discover host decisions.

This is not a substitute for the
[Arch Wiki](https://wiki.archlinux.org/). Prefer short procedures and point at
upstream docs for deep theory.

## Machine facts

| Fact | Value |
|------|--------|
| Distro | Arch Linux |
| Desktop | Hyprland (Wayland) |
| Preferred kernel | `linux-lts` (via `005_ensure_linux_lts.sh`) |
| Root filesystem | btrfs |
| Snapshots | snapper + snap-pac on root |
| Hibernate swap | `/swap/swapfile` (RAM + ~10% buffer) |
| Idle / lock | hypridle + hyprlock (`~/.config/hypr/`) |
| Lid policy | logind `HandleLidSwitch*=ignore`; hypridle owns sleep |
| Audio | PipeWire + WirePlumber |
| Network | NetworkManager |
| AUR helper | yay (paru accepted by install scripts) |
| Package lists | `base.txt`, `aur.txt` in repo root |
| Boot / UKI | systemd-boot + UKI assumed by archinit scripts |
| GPU notes | NVIDIA checks via `009_nvidia_idle_check.sh` when applicable |

Fill in host-local blanks when you know them: hostname, disk device names,
exact btrfs subvolume layout, primary user.

## Baseline "done" checklist

1. Official packages from `base.txt`; selected AUR from `aur.txt`
2. zsh as login shell (`003_ensure_zsh.sh`)
3. `linux-lts` default boot entry (`005_ensure_linux_lts.sh`)
4. Hibernate swap + resume wiring (`006_setup_hibernate_swap.sh`)
5. User units enabled (`007_enable_user_services.sh`)
6. logind lid = ignore; hypridle/hyprlock configs present
7. `./008_healthz.sh` exits `0`

## archinit scripts map

| Script | Concern |
|--------|---------|
| `001_install_packages.sh` | Install official packages from `base.txt` |
| `002_install_aur.sh` | Interactive AUR install from `aur.txt` |
| `003_ensure_zsh.sh` | zsh as default shell |
| `004_configure_git.sh` | Global git identity |
| `005_ensure_linux_lts.sh` | Install/default LTS + UKI preset hygiene |
| `006_setup_hibernate_swap.sh` | `/swap/swapfile`, fstab, resume, mkinitcpio |
| `007_enable_user_services.sh` | Enable units under `~/.config/systemd` |
| `008_healthz.sh` | Read-only baseline audit (see `healthz.md`) |
| `009_nvidia_idle_check.sh` | NVIDIA DRM / VRAM preserve / suspend services |

## Wiki map

### 01 — System

- [overview](/01-system/overview) — layout, users/groups, time
- [pacman](/01-system/pacman) — packages, query, cache
- [yay / AUR](/01-system/yay-aur) — helper install and hygiene
- [systemd](/01-system/systemd) — units, timers, journal
- [kernels and boot](/01-system/kernels-boot) — LTS, UKI, mkinitcpio

### 02 — Storage

- [btrfs](/02-storage/btrfs)
- [snapper](/02-storage/snapper)
- [swap and hibernate](/02-storage/swap-hibernate)
- [CIFS mounts](/02-storage/mounts-cifs)

### 03 — Session

- [loginctl](/03-session/loginctl)
- [Hyprland](/03-session/hyprland)
- [idle, lock, sleep](/03-session/idle-lock-sleep)

### 04 — Desktop

- [PipeWire](/04-desktop/audio-pipewire)
- [NetworkManager](/04-desktop/network-nmcli)
- [Bluetooth](/04-desktop/bluetooth)
- [portals and screenshots](/04-desktop/portals-screenshare)

### 05 — Ops

- [safe updates](/05-ops/updates)
- [backups](/05-ops/backups)
- [health checks](/05-ops/health-checks)

### 06 — Troubleshooting

- [boot and login](/06-troubleshooting/boot-and-login)
- [Hyprland](/06-troubleshooting/hyprland)
- [logind and sleep](/06-troubleshooting/logind-sleep)
- [network and audio](/06-troubleshooting/network-audio)
- [NVIDIA](/06-troubleshooting/nvidia)

### 07 — Reference

- [cheatsheet](/07-reference/cheatsheet)
- [glossary](/07-reference/glossary)
- [links](/07-reference/links)

## Recovery order of preference

1. Boot last known good kernel / fallback UKI
2. Roll back with snapper (read [snapper](/02-storage/snapper) first)
3. Arch ISO → mount btrfs → `arch-chroot` (see [boot and login](/06-troubleshooting/boot-and-login))
4. Restore from restic/rsync only for home data (see [backups](/05-ops/backups))

## Secrets policy

Never put passwords, Wi-Fi PSKs, CIFS credentials, or API tokens in this wiki.
Store credentials in `0600` files outside git (for example under `/etc/cred/`
or a password manager).

## Open questions (fill on the real host)

- Hostname, primary username, timezone
- Exact btrfs subvolume map (`@`, `@home`, snapshot mount opts)
- ESP mount path and systemd-boot entry names
- GPU model and hybrid scheme (iGPU/dGPU, offload tool if any)
- How Hyprland is started (TTY, greetd, SDDM, uwsm, …)
- restic repository location and exclude list (no passwords here)
- Any persistent CIFS/NFS units already in `/etc/fstab`
