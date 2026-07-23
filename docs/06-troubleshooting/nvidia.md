# Troubleshooting: NVIDIA

Use when this laptop drives displays through NVIDIA on Hyprland (including
hybrid layouts). Start with the repo script; it encodes the common Arch
checklist.

## Run the checklist

```bash
cd /path/to/archinit
./009_nvidia_idle_check.sh
```

Collect:

```bash
cat /proc/cmdline
pacman -Q | rg -i 'nvidia|linux'
nvidia-smi
lsmod | rg nvidia
```

## Required pieces (typical modern Arch + Wayland)

1. **Kernel params** (via `/etc/kernel/cmdline` then rebuild UKI):
   - `nvidia_drm.modeset=1`
   - `nvidia_drm.fbdev=1` (important on newer drivers)
2. **Preserve video memory for suspend**:

```bash
# /etc/modprobe.d/nvidia.conf (example)
options nvidia NVreg_PreserveVideoMemoryAllocations=1
```

3. **Suspend services enabled**:

```bash
sudo systemctl enable nvidia-suspend.service
sudo systemctl enable nvidia-hibernate.service
sudo systemctl enable nvidia-resume.service
systemctl is-enabled nvidia-suspend.service nvidia-hibernate.service nvidia-resume.service
```

4. **Idle on-resume dpms** in hypridle: `hyprctl dispatch dpms on`

Rebuild initramfs/UKI after cmdline/modprobe changes:

```bash
sudo mkinitcpio -P
sudo reboot
```

## Early modeset / module load

Early KMS needs nvidia modules available in initramfs on some setups. If
boot graphics fail, compare with Arch Wiki **NVIDIA** and **NVIDIA
(Hotfix)**. hyprland NVIDIA FAQ also tracks env vars like:

```bash
# common session envs — set in your Hyprland/env machinery, not blindly paste secrets
# LIBVA_DRIVER_NAME=nvidia
# __GLX_VENDOR_LIBRARY_NAME=nvidia
# GBM_BACKEND=nvidia-drm
# WLR_NO_HARDWARE_CURSORS=1   # legacy workaround; prefer modern fixes first
```

Confirm which still apply for your driver series before copying old blogs.

## Black screen after wake

1. Pass `009_nvidia_idle_check.sh`
2. Confirm preserve memory option
3. Confirm three nvidia-* services
4. hypridle on-resume dpms
5. Test `systemctl suspend` once from a simple workspace

## Driver / kernel skew after update

```bash
pacman -Q linux linux-lts nvidia nvidia-lts nvidia-dkms 2>/dev/null
uname -r
```

Headers must match the running kernel package family. DKMS builds can fail
silently until reboot — check:

```bash
sudo dkms status
journalctl -b | rg -i 'dkms|nvidia'
```

Prefer pairing **linux-lts** with a matching NVIDIA package path for stability.

## Hybrid GPU (Intel/AMD + NVIDIA)

- Confirm whether Hyprland runs on iGPU or dGPU
- External monitor issues often mean wrong offload / output ownership
- Tools like `uycm`/`envycontrol`/`supergfxctl` (if you install one) change
  modes — document your choice here later once fixed on hardware

<!-- prettier-ignore -->
> [!NOTE]
> Record the exact GPU model and hybrid scheme once known. Until then treat
> this page as a check-list, not a per-SKU pinout diagram.

## If it fails

- Rebuild UKI, reboot both kernels once
- Boot without proprietary modules for recovery TTY (host-specific)
- [boot-and-login](boot-and-login.md) chroot to reinstall nvidia packages
- Fallback: temporary `WLR_RENDERER` / software paths are last-ditch for
  "already in" recovery only
