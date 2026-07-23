# Troubleshooting: boot and login

Recover when the machine does not reach a working graphical session or fails
before userspace is comfortable.

## Collect facts early

From a working TTY (`Ctrl+Alt+F3` often) or chroot:

```bash
uname -r
findmnt -no FSTYPE,SOURCE /
cat /proc/cmdline
bootctl status
journalctl -b -p err --no-pager | tail -80
systemctl --failed
```

## Boot menu fallback

1. Enter systemd-boot menu (often hold Space / Esc per firmware)
2. Boot an alternate UKI (mainline vs LTS, older generation if kept)
3. If only one entry fails with NVIDIA, try the other kernel once

Restore LTS default later with `./005_ensure_linux_lts.sh`.

## Busy emergency or failed mount

- Read the unit that failed (`systemctl status …`)
- `nofail` on non-critical network mounts (see [CIFS](../02-storage/mounts-cifs.md))
- btrfs root corruption → do not write-balance blindly; boot ISO, scrub,
  restore from backup/snapper

## Login works on TTY but not Hyprland

```bash
# as your user on TTY
echo "$XDG_SESSION_TYPE"
Hyprland
# or whatever start path you use (uwsm, start-hyprland, greetd session)
```

Logs:

```bash
journalctl --user -b --no-pager | rg -i 'hypr|wayland|gpu'
ls "$XDG_RUNTIME_DIR"
```

See [Hyprland troubleshooting](hyprland.md).

## After a bad pacman upgrade

```bash
sudo snapper -c root list | tail -20
```

Prefer rolling back the root subvolume with a known-good pre snapshot over
random package downgrades. Procedure depends on layout — Arch Wiki Snapper
restoring section + your `@` / `@home` split.

## Arch ISO recovery skeleton

1. Boot Arch install ISO (match architecture)
2. Networking optional (`iwctl` / Ethernet)
3. Mount ESP and root **with correct subvol**:

```bash
# EXAMPLE only — discover with btrfs subvolume list
mount /dev/nvme0n1p1 /mnt/boot   # ESP path varies
mount -o subvol=@ /dev/nvme0n1p2 /mnt
# mount other subvolumes (@home, …) as your fstab does
```

4. Check `/mnt/etc/fstab` and replicate mounts under `/mnt`
5. Enter chroot:

```bash
arch-chroot /mnt
mkinitcpio -P
bootctl install   # only if bootloader is actually broken
exit
umount -R /mnt
reboot
```

Use `lsblk -f`, `btrfs subvolume list`, and a copy of working fstab if memory
is fuzzy.

## Reinstall kernel from chroot

```bash
pacman -Syu linux-lts linux-lts-headers
mkinitcpio -P
```

## Password / sudo recovery

From chroot:

```bash
passwd youruser
# ensure wheel + sudoers still valid
```

## If it fails

- Cannot find root UUID → `lsblk -f`, fix fstab, do not guess `resume=` UUIDs
- Repeating panic on both kernels → hardware memtest / disk health
- Encrypted root (if you use it) → unlock before mount; not covered by an
  archinit assumption unless you already set it up
