# Troubleshooting: network and audio

Wi-Fi, Ethernet, and sound after sleep or updates.

## Wi-Fi dead

```bash
nmcli general status
nmcli device
rfkill list
ip link
journalctl -u NetworkManager -b -p err --no-pager | tail -50
```

Steps:

1. `rfkill unblock wifi; nmcli radio wifi on`
2. `sudo systemctl restart NetworkManager`
3. Forget/readd connection if the profile is corrupt
4. Check airplane keybind mishaps in hyprland config

More: [network-nmcli](../04-desktop/network-nmcli.md).

## Connected, no connectivity

```bash
nmcli networking connectivity check
ip r
resolvectl query archlinux.org 2>/dev/null || getent hosts archlinux.org
ping -c2 1.1.1.1
ping -c2 archlinux.org
```

Split: fail IP ping → routing/gateway; fail only names → DNS.

## After suspend networking sticky

```bash
nmcli networking off
nmcli networking on
# or
sudo systemctl restart NetworkManager
```

## No audio sinks

```bash
systemctl --user status pipewire wireplumber pipewire-pulse
wpctl status
journalctl --user -u pipewire -u wireplumber -b --no-pager | tail -80
```

Restart:

```bash
systemctl --user restart pipewire pipewire-pulse wireplumber
```

Confirm you are not mixing full PulseAudio daemon install against PipeWire
pulse replacement accidentally.

## Wrong output device

```bash
wpctl status
wpctl set-default <ID>
```

## Bluetooth headset issues

[bluetooth](../04-desktop/bluetooth.md) + sink selection. Re-pair after deep
firmware updates if the MAC stack loses bonding.

## Mic silent

```bash
wpctl status
wpctl get-volume @DEFAULT_AUDIO_SOURCE@
wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 0
```

Check physical mute keys and browser permission.

## If it fails

Still broken after restart of NM/PipeWire → reboot once; then check kernel
firmware packages and `dmesg | rg -i 'wlan|ath|iwl|sof|snd'`.
