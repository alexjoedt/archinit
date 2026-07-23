# Personal Arch + Hyprland wiki

This is not a substitute for the
[Arch Wiki](https://wiki.archlinux.org/). Prefer short procedures and point at
upstream docs for deep theory.

## Machine facts

| Fact | Value |
|------|--------|
| Distro | Arch Linux |
| Desktop | Hyprland (Wayland) |
| Preferred kernel | `linux-lts` (via `ensure_linux_lts.sh`) |
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
| GPU notes | NVIDIA checks via `nvidia_idle_check.sh` when applicable |

Fill in host-local blanks when you know them: hostname, disk device names,
exact btrfs subvolume layout, primary user.

## Baseline "done" checklist

1. Official packages from `base.txt`; selected AUR from `aur.txt`
2. zsh as login shell (`ensure_zsh.sh`)
3. `linux-lts` default boot entry (`ensure_linux_lts.sh`)
4. Hibernate swap + resume wiring (`setup_hibernate_swap.sh`)
5. User units enabled (`enable_user_services.sh`)
6. logind lid = ignore; hypridle/hyprlock configs present
7. `./healthz.sh` exits `0`

## archinit scripts map

| Script | Concern |
|--------|---------|
| `install_packages.sh` | Install official packages from `base.txt` |
| `install_aur.sh` | Interactive AUR install from `aur.txt` |
| `ensure_zsh.sh` | zsh as default shell |
| `configure_git.sh` | Global git identity |
| `ensure_linux_lts.sh` | Install/default LTS + UKI preset hygiene |
| `setup_hibernate_swap.sh` | `/swap/swapfile`, fstab, resume, mkinitcpio |
| `enable_user_services.sh` | Enable units under `~/.config/systemd` |
| `healthz.sh` | Read-only baseline audit (see `healthz.md`) |
| `nvidia_idle_check.sh` | NVIDIA DRM / VRAM preserve / suspend services |

## Wiki map

### 01 — System

- [overview](01-system/overview.md) — layout, users/groups, time
- [pacman](01-system/pacman.md) — packages, query, cache
- [yay / AUR](01-system/yay-aur.md) — helper install and hygiene
- [systemd](01-system/systemd.md) — units, timers, journal
- [kernels and boot](01-system/kernels-boot.md) — LTS, UKI, mkinitcpio

### 02 — Storage

- [btrfs](02-storage/btrfs.md)
- [snapper](02-storage/snapper.md)
- [swap and hibernate](02-storage/swap-hibernate.md)
- [CIFS mounts](02-storage/mounts-cifs.md)

### 03 — Session

- [loginctl](03-session/loginctl.md)
- [Hyprland](03-session/hyprland.md)
- [idle, lock, sleep](03-session/idle-lock-sleep.md)

### 04 — Desktop

- [PipeWire](04-desktop/audio-pipewire.md)
- [NetworkManager](04-desktop/network-nmcli.md)
- [Bluetooth](04-desktop/bluetooth.md)
- [portals and screenshots](04-desktop/portals-screenshare.md)

### 05 — Ops

- [safe updates](05-ops/updates.md)
- [backups](05-ops/backups.md)
- [health checks](05-ops/health-checks.md)

### 06 — Troubleshooting

- [boot and login](06-troubleshooting/boot-and-login.md)
- [Hyprland](06-troubleshooting/hyprland.md)
- [logind and sleep](06-troubleshooting/logind-sleep.md)
- [network and audio](06-troubleshooting/network-audio.md)
- [NVIDIA](06-troubleshooting/nvidia.md)

### 07 — Reference

- [cheatsheet](07-reference/cheatsheet.md)
- [glossary](07-reference/glossary.md)
- [links](07-reference/links.md)

## Recovery order of preference

1. Boot last known good kernel / fallback UKI
2. Roll back with snapper (read [snapper](02-storage/snapper.md) first)
3. Arch ISO → mount btrfs → `arch-chroot` (see [boot and login](06-troubleshooting/boot-and-login.md))
4. Restore from restic/rsync only for home data (see [backups](05-ops/backups.md))

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