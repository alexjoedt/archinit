# snapper and snap-pac

Filesystem snapshots for root. **snap-pac** hooks pacman so upgrades get automatic
pre/post snapshots when configured.

## Prerequisites

```bash
pacman -Q snapper snap-pac btrfs-progs
findmnt -no FSTYPE /
ls /etc/snapper/configs/
sudo snapper list-configs
```

Root config is typically named `root` with config file
`/etc/snapper/configs/root`.

## Timers

```bash
systemctl status snapper-timeline.timer snapper-cleanup.timer
systemctl is-enabled snapper-timeline.timer snapper-cleanup.timer
```

Enable if missing (root):

```bash
sudo systemctl enable --now snapper-timeline.timer
sudo systemctl enable --now snapper-cleanup.timer
```

## List and inspect

```bash
sudo snapper -c root list
sudo snapper -c root list --columns number,date,description,user
```

Show changes between snapshots:

```bash
sudo snapper -c root status BEGIN..END
sudo snapper -c root diff BEGIN..END
sudo snapper -c root diff BEGIN..END /etc/fstab
```

## Create a manual snapshot

```bash
sudo snapper -c root create --description "before risky change"
```

## undochange (file-level)

Restore selected paths from a snapshot pair (read man carefully):

```bash
sudo snapper -c root undochange BEGIN..END /path/to/file
```

This is not always a full system rollback. Prefer explicit rollback workflow
for "boot is cooked".

## Rollback patterns

Exact steps depend on your subvolume layout and whether you boot into a
read-only snapshot. High-level:

1. Boot a known-good environment (select older snapshot from boot menu if
   configured, or use Arch ISO)
2. Identify pre-upgrade snapshot numbers from `snapper list`
3. Follow Arch Wiki **Snapper** + **Snapper#Restoring** for your layout, or use
   the distribution's snapper-gui/brtl helpers if installed
4. Rebuild initramfs/UKI if kernel/initram packages were involved
5. Reboot and run `008_healthz.sh`

<!-- prettier-ignore -->
> [!WARNING]
> Rollback can discard newer data on the rolled-back subvolume. Confirm
> `/home` layout (separate subvolume?) so you do not surprise yourself.

## snap-pac

With `snap-pac` installed, pacman transactions create snapshots automatically.
Descriptions often mention the pacman transaction.

```bash
sudo snapper -c root list | tail
```

If no pre/post pairs appear after `-Syu`, fix snapper root config and pacman
hook packages before relying on rollback.

## Cleanup

```bash
sudo snapper -c root list
sudo snapper -c root delete NUMBER
# or ranges per snapper manpage
sudo snapper -c root cleanup number
sudo snapper -c root cleanup timeline
```

Configure retention in `/etc/snapper/configs/root` (`NUMBER_LIMIT`, timeline
limits). Leaving unlimited snapshots fills the disk.

## If it fails

- No configs → create root config (`snapper create-config /`) then review
  subvolume `.snapshots` mount conventions for your install
- Quota / ENOSPC → delete old snapshots first
- After rollback keyboard/disk still wrong → [boot recovery](../06-troubleshooting/boot-and-login.md)
