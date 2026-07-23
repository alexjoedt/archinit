# Hyprland and hyprctl

Wayland compositor control. Config lives under `~/.config/hypr/`. Related
stack on this host: hyprpaper, hyprsunset, hyprlock, hypridle, hyprpicker,
grim/slurp/satty, xdg-desktop-portal-hyprland.

## Config layout (expected)

```text
~/.config/hypr/
  hyprland.conf          # main (or modular includes)
  hypridle.conf
  hyprlock.conf
  # wallpapers, rules, etc.
```

Edit, then reload when possible.

## hyprctl essentials

```bash
hyprctl version
hyprctl reload
hyprctl monitors
hyprctl clients
hyprctl workspaces
hyprctl activewindow
hyprctl devices
hyprctl animations
```

Dispatch compositor commands:

```bash
hyprctl dispatch workspace 2
hyprctl dispatch dpms on
hyprctl dispatch dpms off
hyprctl dispatch exit          # leaves compositor — ends graphical session path
```

Set a keyword live (temporary until reload/restart):

```bash
hyprctl keyword general:gaps_in 5
```

Batch / JSON:

```bash
hyprctl -j monitors | jq
hyprctl -j clients | jq '.[].class'
```

## Reload vs restart vs logout

| Action | When |
|--------|------|
| `hyprctl reload` | Most config changes |
| Kill and relaunch Hyprland from TTY/display manager | Broken socket, GPU reset, hard fail loop |
| Full logout / reboot | Input groups changed, NVIDIA driver updated, session corruption |

`dispatch exit` ends the compositor; know how you start Hyprland again —
preferred path on this wiki is [greetd + ReGreet](greetd.md) (else UWSM, SDDM,
or TTY + `Hyprland`).

## Screenshots and clipboard

Packages from `base.txt`: `grim`, `slurp`, `satty`, `wl-clipboard`, `cliphist`.

Examples:

```bash
grim - | satty -f -
grim -g "$(slurp)" - | wl-copy
wl-paste
cliphist list | head
```

Wire binds in hyprland.conf to match muscle memory.

## Monitors

```bash
hyprctl monitors
# then set in config, e.g. monitor=eDP-1,preferred,auto,1
hyprctl reload
```

For mirror/projector one-shots, prefer config or a small script over memory
of opaque keyword strings.

## Portals

```bash
systemctl --user status xdg-desktop-portal xdg-desktop-portal-hyprland
```

Screenshare and file picker depend on portals —
[portals-screenshare](../04-desktop/portals-screenshare.md).

## If it fails

See dedicated [Hyprland troubleshooting](../06-troubleshooting/hyprland.md).
Quick checks:

```bash
echo "$XDG_CURRENT_DESKTOP" "$XDG_SESSION_TYPE"
ls "$XDG_RUNTIME_DIR/hypr" 2>/dev/null
hyprctl version
journalctl --user -b | rg -i hypr
```
