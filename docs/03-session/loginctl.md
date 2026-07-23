# loginctl and sessions

systemd-logind tracks seats, sessions, and sleep inhibitors. Hyprland runs
inside a user graphical session; lid policy is owned by logind **and**
hypridle on this laptop — see [idle-lock-sleep](idle-lock-sleep.md).

## List sessions

```bash
loginctl
loginctl list-sessions
loginctl list-users
loginctl list-seats
loginctl user-status
loginctl session-status
```

Pick a session ID from the first column:

```bash
loginctl show-session SESSION_ID -p Type -p Class -p Active -p State -p Display -p Remote
loginctl show-user "$USER"
```

Graphical Wayland sessions usually report `Type=wayland`.

## Lock / unlock / terminate

```bash
loginctl lock-session
loginctl unlock-session
loginctl lock-sessions
loginctl terminate-session SESSION_ID
loginctl terminate-user "$USER"
```

`hyprlock` is the preferred on-screen lock; loginctl lock should integrate via
session tools when wired. Prefer hyprlock bindings for day-to-day locking.

## Linger

Lingering keeps a user manager without an interactive login (user services
survive logout).

```bash
loginctl show-user "$USER" -p Linger
sudo loginctl enable-linger "$USER"
sudo loginctl disable-linger "$USER"
```

Only enable linger if you intentionally want user services headless. It is
**not** required for normal Hyprland use.

## Inhibitors (what blocks sleep)

```bash
systemd-inhibit --list
loginctl show-session SESSION_ID -p InhibitorsDelayMaxUSec
```

Apps can block idle/sleep (for example video players). If the machine never
suspends, check inhibitors before blaming hypridle.

## Properties useful on this host

```bash
loginctl show-session SESSION_ID -a | rg -i 'type|state|active|display|desktop|remote|idle'
```

## Relation to Hyprland

- You need an active seat session for GPU/input
- Killing the session ends the compositor
- `systemctl --user` talks to the user bus of that login

If `hyprctl` fails with socket errors, you are often on the wrong TTY user
session or Hyprland is dead — [hyprland](hyprland.md).

## If it fails

- Empty `loginctl` as user → not on a logind session (odd environments)
- Cannot lock → check hyprlock package + keybinds and portal bits
- Sleep blocked → `systemd-inhibit --list`, then [logind-sleep](../06-troubleshooting/logind-sleep.md)
