# PipeWire audio

User-session audio stack: **PipeWire** with **WirePlumber**, Pulse compat
via `pipewire-pulse`. Packages are declared in `base.txt`.

## Status

```bash
systemctl --user status pipewire pipewire-pulse wireplumber
pgrep -a pipewire
wpctl status
```

## Volume and defaults

```bash
wpctl status
wpctl get-volume @DEFAULT_AUDIO_SINK@
wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.5
wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
wpctl set-default <ID>
```

Pulse-compat tools still often work:

```bash
pactl info
pactl list short sinks
pactl set-default-sink <name>
```

Media keys / players: `playerctl`.

## Restart audio user stack

```bash
systemctl --user restart wireplumber pipewire pipewire-pulse
```

If the session bus is confused, log out of Hyprland and back in.

## Bluetooth headsets

Start Bluetooth (system), pair, then select sink with `wpctl`. See
[bluetooth](bluetooth.md). If the profile sticks on HSP/HFP hands-free with
bad quality, switch to A2DP in `pavucontrol` or with WirePlumber tools when
available.

## ALSA sanity

```bash
pacman -Q alsa-utils
amixer
# speaker-test -c 2
```

## If it fails

- No sinks → `wpctl status`, user services failed (`journalctl --user -u pipewire -b`)
- Flatpak no sound → portal/pipewire permissions; reinstall portal stack
- After update silence → restart user audio units; confirm no leftover PulseAudio
  package fight (`pacman -Q pulseaudio` should not conflict on a pure PipeWire setup)

More recipes: [network-audio troubleshooting](../06-troubleshooting/network-audio.md).
