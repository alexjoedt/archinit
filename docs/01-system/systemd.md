# systemd essentials

Manage services, timers, and logs. This host uses **system** units for logind,
NetworkManager, bluetooth, snapper timers, and **user** units under
`~/.config/systemd/user/` (enable via `007_enable_user_services.sh`).

## System vs user

| Scope | Command prefix | Typical units |
|-------|----------------|---------------|
| System | `systemctl` (often needs root) | NetworkManager, bluetooth, snapper timers |
| User | `systemctl --user` | app daemons, portals started per session |

User bus requires a logged-in session (or lingering). See [loginctl](../03-session/loginctl.md).

## Status and control

```bash
systemctl status NetworkManager
systemctl is-enabled NetworkManager
sudo systemctl enable --now bluetooth.service
sudo systemctl restart NetworkManager
sudo systemctl stop some.service
```

User:

```bash
systemctl --user status
systemctl --user enable --now some.service
systemctl --user daemon-reload   # after editing unit files
```

List failed units:

```bash
systemctl --failed
systemctl --user --failed
```

## Timers (prefer over cron here)

```bash
systemctl list-timers --all
systemctl list-timers --user --all
systemctl status snapper-timeline.timer
systemctl status snapper-cleanup.timer
```

Inspect what a timer triggers:

```bash
systemctl cat snapper-timeline.timer
```

## Journal

```bash
journalctl -bঘর # this boot
journalctl -b -p err      # errors and worse
journalctl -b -p warning
journalctl -u NetworkManager -b
journalctl -f             # follow
journalctl --user -b
journalctl -b -1          # previous boot
```

## Restart policy and edits

Prefer drop-ins over editing vendor units:

```bash
sudo systemctl edit some.service
sudo systemctl daemon-reload
sudo systemctl restart some.service
```

## logind config effective values

```bash
systemd-analyze cat-config systemd/logind.conf
```

Lid keys must be `ignore` on this laptop so hypridle owns sleep. Details:
[idle-lock-sleep](../03-session/idle-lock-sleep.md).

## Enable units from archinit

```bash
cd /path/to/archinit
./007_enable_user_services.sh
# DRY_RUN=1 ASSUME_YES=1 ./007_enable_user_services.sh
```

## If it fails

- `Failed to connect to bus` (user) → no session; log in graphically or on a
  seat, or enable linger carefully
- unit start loops → `journalctl -u name -b` and set log level
- after editing units forgot reload → `daemon-reload`
