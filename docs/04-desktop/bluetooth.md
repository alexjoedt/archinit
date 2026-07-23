# Bluetooth

Uses **bluez** + **bluez-utils** (`bluetoothctl`). Enable the system service
once, then pair from the user session.

## Service

```bash
systemctl status bluetooth
sudo systemctl enable --now bluetooth
```

## bluetoothctl basics

```bash
bluetoothctl
# inside:
power on
agent on
default-agent
scan on
# note MAC
pair MAC
trust MAC
connect MAC
devices
info MAC
quit
```

Non-interactive examples:

```bash
bluetoothctl power on
bluetoothctl devices
bluetoothctl connect AA:BB:CC:DD:EE:FF
```

## Audio routing

After connect, select the headset sink:

```bash
wpctl status
wpctl set-default <ID>
```

## Soft blocks

```bash
rfkill list bluetooth
rfkill unblock bluetooth
```

## If it fails

- Controller missing → `lsusb`/`btop` not relevant; check `dmesg | rg -i blue`
  and firmware packages
- Pairs but no sound → PipeWire BT modules, A2DP profile
  ([audio](audio-pipewire.md))
- Drops after suspend → BIOS power quirks / NVIDIA resume; recheck connection
  after wake
