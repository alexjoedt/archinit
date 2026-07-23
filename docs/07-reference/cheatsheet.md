# Cheatsheet

Dense commands used on this machine. Prefer the topic pages when you need
context.

## Packages

```bash
sudo pacman -Syu
pacman -Qs keyword
pacman -Qo /path
pacman -Ql pkg
pacman -Qdt
yay -Syu
pacman -Qm
./install_packages.sh
./install_aur.sh
```

## systemd / logs

```bash
systemctl --failed
systemctl status UNIT
systemctl --user status
journalctl -b -p err
journalctl -u UNIT -b
systemctl list-timers --all
```

## Sessions

```bash
loginctl
loginctl lock-session
systemd-inhibit --list
```

## Hyprland

```bash
hyprctl version
hyprctl reload
hyprctl monitors
hyprctl clients
hyprctl dispatch dpms on
hyprctl dispatch exit
```

## Storage / snapper / swap

```bash
findmnt -no FSTYPE,SOURCE,OPTIONS /
sudo btrfs subvolume list /
sudo snapper -c root list
sudo snapper -c root create -d 'note'
swapon --show
ls -lh /swap/swapfile
cat /proc/cmdline
./setup_hibernate_swap.sh --dry-run
```

## Network / audio / BT

```bash
nmcli device wifi list
nmcli device wifi connect SSID --ask
rfkill list
wpctl status
wpctl set-default ID
bluetoothctl
```

## Boot

```bash
bootctl status
bootctl list
uname -r
sudo mkinitcpio -P
./ensure_linux_lts.sh --dry-run
```

## Screenshots / clipboard

```bash
grim -g "$(slurp)" - | wl-copy
grim - | satty -f -
wl-paste
```

## Health

```bash
./healthz.sh
./nvidia_idle_check.sh
```

## CIFS

```bash
sudo mount -t cifs //server/share /mnt/share -o credentials=/etc/cred/FILE,uid=$(id -u),gid=$(id -g)
sudo umount -l /mnt/share
```
