# Safe update ritual

Update the system without painting yourself into a corner. snap-pac, free
space, and a deliberate reboot window matter more than raw speed.

## 1. Pre-flight

```bash
df -hT /
free -h
sudo snapper -c root list | tail
checkupdates 2>/dev/null || pacman -Qu
./healthz.sh   # from archinit; note WARN/FAIL baseline
```

Postpone bulk upgrades if disk is nearly full or healthz already FAIL on
swap/snapper.

## 2. Official packages

```bash
sudo pacman -Syu
```

If the transaction is huge (toolchain, GTK, Qt, kernel), ensure you can stay
at the keyboard for a reboot.

## 3. AUR packages

```bash
yay -Syu
# or only outdated AUR:
pacman -Qm
```

Rebuild broken `-git` packages when soname bumps appear.

## 4. Boot-critical changes

If kernels, NVIDIA modules, mkinitcpio hooks, or systemd-boot entries
changed:

```bash
bootctl status
cat /proc/cmdline
# LTS default hygiene when needed:
./ensure_linux_lts.sh --dry-run
sudo mkinitcpio -P   # if not already triggered by pacman hooks
```

Reboot into the intended kernel before deep work:

```bash
systemctl reboot
```

## 5. Post-check

```bash
uname -r
./healthz.sh
systemctl --failed
systemctl --user --failed
wpctl status | head
nmcli general status
```

Optional NVIDIA:

```bash
./nvidia_idle_check.sh
```

## 6. When something is wrong after reboot

1. Snap shot pre-upgrade pair in `snapper list` — consider rollback
2. Boot secondary UKI / older entry
3. [boot-and-login](../06-troubleshooting/boot-and-login.md) from ISO if needed

## Cadence tips

- Prefer one focused `-Syu` session over hundreds of micro upgrades if you
  snapshot: less churn for snap-pac disk use
- Never mix untested partial upgrades (`-S pkg` while partially stale) as a
  habit on Arch — keep the system generally synced
- Read pacman output for `.pacnew` files:

```bash
pacdiff -o   # if pacman-contrib tools available
find /etc -name '*.pacnew' 2>/dev/null
```

## If it fails mid-transaction

```bash
sudo rm -f /var/lib/pacman/db.lck
sudo pacman -Syu
```

Interrupted upgrades that leave the system unbootable → recovery ISO +
snapper, not another random `-Syyuu` hope-loop.
