# NetworkManager (nmcli)

NetworkManager is the network stack for this host (`networkmanager` in
`base.txt`).

## Status

```bash
systemctl status NetworkManager
nmcli general status
nmcli device
nmcli connection show
nmcli networking connectivity check
```

## Wi-Fi

```bash
nmcli device wifi rescan
nmcli device wifi list
nmcli device wifi connect 'SSID' --ask
nmcli connection up 'SSID'
nmcli connection down 'SSID'
```

Radio soft-blocks:

```bash
rfkill list
rfkill unblock wifi
nmcli radio wifi on
```

## Wired

```bash
nmcli device connect eth0    # use your ifname from nmcli device
nmcli connection show --active
```

## DNS and IP peek

```bash
nmcli dev show | rg -i 'ip4|ip6|dns|general.device'
resolvectl status 2>/dev/null || cat /etc/resolv.conf
ip -br a
ip r
```

## Airplane / off

```bash
nmcli radio all off
nmcli networking off
nmcli networking on
```

## Logs

```bash
journalctl -u NetworkManager -b -p err
journalctl -u NetworkManager -b --no-pager | tail -100
```

## If it fails

- Device unavailable → `rfkill`, hardware killswitch, `ip link`
- Connected but no internet → default route, DNS, captive portal
- After sleep → `nmcli networking off && nmcli networking on` or restart NM

See [network-audio troubleshooting](../06-troubleshooting/network-audio.md).
