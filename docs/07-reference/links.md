# Links

Upstream references. Prefer these when this wiki is thin.

## Arch Wiki (high value)

- [General recommendations](https://wiki.archlinux.org/title/General_recommendations)
- [System maintenance](https://wiki.archlinux.org/title/System_maintenance)
- [pacman](https://wiki.archlinux.org/title/Pacman)
- [AUR](https://wiki.archlinux.org/title/Arch_User_Repository)
- [systemd](https://wiki.archlinux.org/title/Systemd)
- [systemd-logind](https://wiki.archlinux.org/title/Systemd-logind)
- [btrfs](https://wiki.archlinux.org/title/Btrfs)
- [Snapper](https://wiki.archlinux.org/title/Snapper)
- [Power management/Suspend and hibernate](https://wiki.archlinux.org/title/Power_management/Suspend_and_hibernate)
- [swap](https://wiki.archlinux.org/title/Swap)
- [systemd-boot](https://wiki.archlinux.org/title/Systemd-boot)
- [mkinitcpio](https://wiki.archlinux.org/title/Mkinitcpio)
- [Unified kernel image](https://wiki.archlinux.org/title/Unified_kernel_image)
- [NetworkManager](https://wiki.archlinux.org/title/NetworkManager)
- [PipeWire](https://wiki.archlinux.org/title/PipeWire)
- [Bluetooth](https://wiki.archlinux.org/title/Bluetooth)
- [Samba / CIFS](https://wiki.archlinux.org/title/Samba)
- [NVIDIA](https://wiki.archlinux.org/title/NVIDIA)
- [NVIDIA (Hotfix?)](https://wiki.archlinux.org/title/NVIDIA#Installation) —
  stay on the current page for driver install pairing with kernels
- [Arch boot process](https://wiki.archlinux.org/title/Arch_boot_process)
- [Improve boot performance](https://wiki.archlinux.org/title/Improving_performance) —
  only when needed

## Display manager / greeter

- [greetd](https://wiki.archlinux.org/title/Greetd)
- [ReGreet](https://github.com/rharish101/ReGreet)
- [cage](https://github.com/Hjdskes/cage)
- Local procedure: [greetd + ReGreet](../03-session/greetd.md)

## Hyprland

- [Hyprland wiki](https://wiki.hyprland.org/)
- [hypridle](https://wiki.hyprland.org/Hypr-Ecosystem/hypridle/)
- [hyprlock](https://wiki.hyprland.org/Hypr-Ecosystem/hyprlock/)
- [xdg-desktop-portal-hyprland](https://wiki.hyprland.org/Hypr-Ecosystem/xdg-desktop-portal-hyprland/)

## Local repo

From archinit root:

| Doc / script | Role |
|--------------|------|
| `wiki.md` | Generator prompt for this tree |
| `healthz.md` / `008_healthz.sh` | Baseline audit |
| `006_setup_hibernate_swap.sh` | Hibernate swapfile automation |
| `005_ensure_linux_lts.sh` | LTS default + UKI preset |
| `009_nvidia_idle_check.sh` | NVIDIA suspend/DPMS checklist |
| `base.txt` / `aur.txt` | Desired package set |

## When to extend this wiki

Add a page when you fix something once and will forget it: hybrid GPU mode,
exact subvolume map, hosts-specific CIFS units, restic repository location
(without secrets).
