# System overview

Identity of this machine: what a healthy install looks like, where config
lives, and which groups matter for a Hyprland laptop.

## Confirm you are on Arch

```bash
cat /etc/arch-release
uname -r
hostnamectl
```

## Filesystem and layout (expected)

| Path | Role |
|------|------|
| `/` | btrfs root (snapper tracked) |
| `/swap/swapfile` | hibernate-capable swapfile (not inside snapshotted clutter if possible) |
| `/boot` or ESP | EFI + UKIs / bootloader (confirm with `bootctl status`) |
| `~/.config/hypr/` | Hyprland, hypridle, hyprlock |
| `/etc/systemd/logind.conf(.d/)` | lid handling must be `ignore` |

Inspect mounts:

```bash
findmnt -R /
findmnt -no FSTYPE,SOURCE,OPTIONS /
lsblk -f
```

## Users, groups, sudo

Common groups for this desktop stack:

| Group | Why |
|-------|-----|
| `wheel` | sudo |
| `video` | GPU / brightness on some setups |
| `input` | raw input devices when needed |
| `lp` | printers if used |
| `network` / `netdev` | rare; NetworkManager usually needs no extra group |

```bash
id
groups
sudo -l
```

After changing group membership, **log out and back in** (or reboot). New
groups do not apply to already-running sessions.

## Config ownership

| Location | Owner | Notes |
|----------|--------|------|
| `~/.config/`, `~/.local/` | user | Hyprland, apps, user systemd |
| `/etc/` | root | logind, fstab, mkinitcpio, kernel cmdline |
| this repo | user | package lists + maintenance scripts |

Do not commit `/etc` secrets or `~/.ssh` private keys into archinit.

## Time and locale

```bash
timedatectl
timedatectl set-ntp true    # root or polkit
localectl status
```

Set timezone only if wrong:

```bash
sudo timedatectl set-timezone Europe/Berlin   # example
```

## Shell

zsh is the intended interactive shell (`ensure_zsh.sh`).

```bash
echo "$SHELL"
getent passwd "$USER"
```

## Secrets and keyring

- desktop secrets: gnome-keyring / seahorse (packages in `base.txt`)
- SSH: `openssh`; prefer agent or password manager over loose key copies
- never store CIFS passwords in world-readable fstab options

## Hardware peek

```bash
lscpu | head
free -h
df -hT /
upower -e
upower -i $(upower -e | grep BAT) 2>/dev/null
brightnessctl
```

Firmware updates when hardware supports LVFS:

```bash
fwupdmgr get-devices
fwupdmgr refresh
fwupdmgr get-updates
```

## If it fails

- Wrong FS type or missing snapper → [btrfs](../02-storage/btrfs.md), [health checks](../05-ops/health-checks.md)
- Cannot sudo → fix `wheel` membership from a root TTY or recovery ISO
- Time wildly wrong → `timedatectl` + RTC; bad time breaks TLS and pacman
