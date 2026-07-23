# Portals, screenshare, and screenshots

`xdg-desktop-portal` plus **`xdg-desktop-portal-hyprland`** provide file
dialogs, screen capture permission, and related desktop integration under
Hyprland. Screenshots often bypass portals via grim/slurp.

## Check portal stack

```bash
pacman -Q xdg-desktop-portal xdg-desktop-portal-hyprland
systemctl --user status xdg-desktop-portal xdg-desktop-portal-hyprland
systemctl --user restart xdg-desktop-portal xdg-desktop-portal-hyprland
```

Environment usually needed in the session (set by compositor or launcher):

```bash
echo "$XDG_CURRENT_DESKTOP"
echo "$XDG_SESSION_TYPE"
```

Prefer `XDG_CURRENT_DESKTOP` containing `Hyprland`.

## Screenshare (browsers / OBS)

1. Confirm portal units are active
2. Start share; approve picker if shown
3. If no windows listed, restart portals and browser

```bash
systemctl --user restart xdg-desktop-portal-hyprland xdg-desktop-portal
```

PipeWire is required for modern capture (`base.txt` includes pipewire stack).

## Screenshots (grim / slurp / satty)

```bash
grim ~/Pictures/screen.png
grim -g "$(slurp)" ~/Pictures/region.png
grim -g "$(slurp)" - | satty -f -
grim - | wl-copy
```

These do not replace portal-based share into browsers but are ideal for local
captures and binds in hyprland.conf.

## Clipboard

```bash
wl-copy <<< 'hello'
wl-paste
# history (if cliphist running)
cliphist list | head
```

## If it fails

| Symptom | Try |
|---------|-----|
| Empty share picker | portal-hyprland installed/running; session type `wayland` |
| Permission denied in browser | restart portals; check browser Wayland flags |
| Black share | GPU/NVIDIA capture quirks; update; try OBS PipeWire source |
| grim fails | `$WAYLAND_DISPLAY` set; run inside Hyprland session |

See also [Hyprland](../03-session/hyprland.md) troubleshooting.
