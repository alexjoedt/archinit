# Troubleshooting: Hyprland

Graphical session, monitors, input, and portal failures under Hyprland.

## Black screen after login

1. Switch to TTY (`Ctrl+Alt+F3`), log in
2. Confirm session remnants:

```bash
loginctl
pgrep -a Hyprland
ls "$XDG_RUNTIME_DIR/hypr" 2>/dev/null
```

3. Check GPU / NVIDIA stack if applicable ([nvidia](nvidia.md))
4. Launch with logs:

```bash
Hyprland > /tmp/hyprland.log 2>&1
```

5. Bisect config: move `~/.config/hypr` aside and try a minimal conf

```bash
mv ~/.config/hypr ~/.config/hypr.bak
# start again; then restore pieces
```

## hyprctl cannot connect

```bash
echo "disp=$WAYLAND_DISPLAY runtime=$XDG_RUNTIME_DIR"
hyprctl instances
```

You are not on the Hyprland session (SSH without proper env, wrong user, or
compositor dead). Run hyprctl as the graphical user on that machine.

## Wrong monitor layout / scaled mess

```bash
hyprctl monitors
# fix monitor= lines in hyprland.conf
hyprctl reload
```

Disable auto multi-monitor experiments until the laptop panel alone works.

## Keyboard layout stuck

```bash
hyprctl devices
# input:kb_layout in config
hyprctl reload
localectl status
```

Group membership changes require re-login.

## Crashes / freezes

```bash
journalctl --user -b | rg -i hypr
dmesg --level=err,warn | tail
```

Note NVIDIA sleeps and dpms paths: [idle-lock-sleep](../03-session/idle-lock-sleep.md).

## Portals / screenshare

[portals-screenshare](../04-desktop/portals-screenshare.md)

```bash
systemctl --user restart xdg-desktop-portal-hyprland xdg-desktop-portal
```

## High CPU of hyprland

- animations / blur heavy on iGPU
- infinite wallpaper script
- monitor connect loop — check udev / cable

## Full exit

```bash
hyprctl dispatch exit
```

Then restart from your display manager or TTY starter.

## If it fails

Still dead after minimal config + other kernel →
[boot-and-login](boot-and-login.md) and GPU driver reinstall from chroot.
