# systemd timers

A timer starts a matching service on a schedule. Prefer timers over cron on
this host: logs land in the journal, units can declare dependencies, and the
same tools cover system and user jobs.

Pair units share a name: `job.timer` decides **when**, `job.service` decides
**what**.

## Timer vs cron

| | systemd timer | cron |
|---|---------------|------|
| Logs | `journalctl -u job.service` | mail or ad-hoc redirects |
| Dependencies | `After=`, `Requires=`, `Wants=` | none built in |
| Missed runs | `Persistent=true` runs once after boot | job is skipped while off |
| Scope | system or `systemctl --user` | user crontab / `/etc/cron.*` |
| Delay jitter | `RandomizedDelaySec=` | external `sleep $RANDOM` hacks |
| Accuracy | calendar or monotonic (`OnBootSec=`) | typically whole minutes |

Use a timer unless a package only ships crontab entries and converting is not
worth it.

## Calendar vs monotonic

**Calendar** (`OnCalendar=`) fires at wall-clock times:

| Expression | Meaning |
|------------|---------|
| `daily` | every day at 00:00 |
| `weekly` | Monday 00:00 |
| `*-*-* 03:30:00` | every day at 03:30 |
| `Mon *-*-* 09:00:00` | Mondays at 09:00 |
| `hourly` | top of each hour |

Check syntax:

```bash
systemd-analyze calendar '*-*-* 03:30:00'
systemd-analyze calendar 'Mon *-*-* 09:00:00'
```

**Monotonic** fires relative to boot or the last run:

```ini
OnBootSec=15min
OnUnitActiveSec=6h
```

You can combine both in one timer.

## Create a system timer

Example: run `/usr/local/bin/home-backup` daily at 02:30, catch up if the
machine was off, add up to 10 minutes of jitter.

1. Service (`/etc/systemd/system/home-backup.service`):

```ini
[Unit]
Description=Home backup (restic)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/home-backup
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
```

2. Timer (`/etc/systemd/system/home-backup.timer`):

```ini
[Unit]
Description=Daily home backup

[Timer]
OnCalendar=*-*-* 02:30:00
Persistent=true
RandomizedDelaySec=10m
Unit=home-backup.service

[Install]
WantedBy=timers.target
```

`Unit=` is optional when the service shares the timer basename
(`home-backup.timer` → `home-backup.service`).

3. Enable and verify:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now home-backup.timer
systemctl list-timers home-backup.timer
systemctl status home-backup.timer
systemctl start home-backup.service    # run once now
journalctl -u home-backup.service -b
```

## Create a user timer

Same shape under `~/.config/systemd/user/`. No root. The user bus must be up
(graphical login, or linger — see [loginctl](../03-session/loginctl.md)).

```bash
mkdir -p ~/.config/systemd/user
# write ~/.config/systemd/user/my-job.service and my-job.timer
systemctl --user daemon-reload
systemctl --user enable --now my-job.timer
systemctl --user list-timers --all
journalctl --user -u my-job.service -b
```

## Inspect and control

```bash
systemctl list-timers --all
systemctl list-timers --user --all
systemctl cat snapper-timeline.timer
systemctl status snapper-timeline.timer
systemctl show snapper-timeline.timer -p NextElapseUSecRealtime -p LastTriggerUSec
```

On this host, snapper uses system timers:

```bash
systemctl status snapper-timeline.timer snapper-cleanup.timer
```

See [snapper](../02-storage/snapper.md) and [systemd](systemd.md).

## Useful timer knobs

| Directive | Role |
|-----------|------|
| `OnCalendar=` | wall-clock schedule (repeatable) |
| `OnBootSec=` | delay after boot |
| `OnUnitActiveSec=` | delay after the service last activated |
| `Persistent=true` | run once after boot if a calendar trigger was missed |
| `RandomizedDelaySec=` | spread load across machines / avoid thundering herd |
| `AccuracySec=` | how tightly to hit the schedule (default is fine) |
| `WakeSystem=true` | wake from suspend for the job (use sparingly) |

## If it fails

- Timer enabled but never fires → `systemctl list-timers --all`; check
  `OnCalendar` with `systemd-analyze calendar`; confirm `daemon-reload`
- Service fails, timer looks fine → `journalctl -u name.service -b`; fix the
  service, not the timer
- User timer silent after logout → enable linger only if you intend
  headless user jobs; otherwise keep it session-bound
- Missed overnight run → set `Persistent=true` on the timer
- Edited unit, no change → `daemon-reload`, then `restart name.timer`
