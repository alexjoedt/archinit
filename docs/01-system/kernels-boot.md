# Kernels and boot

Prefer **linux-lts** as the default boot target. archinit manages this with
`005_ensure_linux_lts.sh` and expects **systemd-boot** with **UKI** (unified kernel
image) style presets when those files exist.

## Inspect current boot

```bash
uname -r
bootctl status
bootctl list
cat /proc/cmdline
cat /etc/kernel/cmdline 2>/dev/null
```

Installed kernels:

```bash
pacman -Q 'linux*'
ls /usr/lib/modules
```

## Ensure LTS is default

From the archinit repo:

```bash
./005_ensure_linux_lts.sh --dry-run
./005_ensure_linux_lts.sh
# fully non-interactive hint suppression:
./005_ensure_linux_lts.sh --yes
```

What it aims to do:

1. Install `linux-lts` (and matching headers if the mainline set has them)
2. Prefer LTS as systemd-boot default (`bootctl set-default` when needed)
3. Diagnose/fix `/etc/mkinitcpio.d/linux-lts.preset` so UKI build matches
   the mainline preset pattern

Options: `--skip-bootloader`, `--no-reboot`, `--dry-run`, `--yes`.

## mkinitcpio and UKI

```bash
cat /etc/mkinitcpio.conf
ls /etc/mkinitcpio.d/
sudo mkinitcpio -P
```

Rebuild a single preset:

```bash
sudo mkinitcpio -p linux-lts
```

Hibernate needs the **`resume` hook** in `HOOKS=` and matching cmdline
`resume=` / `resume_offset=`. See [swap-hibernate](../02-storage/swap-hibernate.md).

## Kernel cmdline (this host)

Scripts that edit cmdline target **`/etc/kernel/cmdline`** (UKI / kernel-install
style). After edits:

```bash
sudo mkinitcpio -P
# or the rebuild path 005_ensure_linux_lts / 006_setup_hibernate_swap uses
```

NVIDIA Wayland-related parameters (when on NVIDIA) often include:

- `nvidia_drm.modeset=1`
- `nvidia_drm.fbdev=1`

Confirm with `009_nvidia_idle_check.sh` and [NVIDIA troubleshooting](../06-troubleshooting/nvidia.md).

## Fallback entries

Keep at least one known-good entry (mainline or older LTS UKI). From the boot
menu, pick an alternate image when the default fails.

```bash
bootctl list
ls -l /efi/EFI/Linux 2>/dev/null || ls -l /boot/EFI/Linux 2>/dev/null
```

ESP path varies; trust `bootctl status`.

## When you must reboot

- New kernel ABI vs modules
- initramfs / UKI rebuild after hook or cmdline changes
- NVIDIA driver major bumps

## If it fails

- Boots wrong kernel → `bootctl list` and set default; re-run `005_ensure_linux_lts.sh`
- Emergency shell / failed UKI → ISO recovery
  ([boot-and-login](../06-troubleshooting/boot-and-login.md))
- Resume from hibernate broken → verify cmdline after kernel package updates
