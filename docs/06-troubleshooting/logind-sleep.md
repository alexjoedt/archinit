# Troubleshooting: logind and sleep

Lid, suspend, hibernate, and double-policy fights.

## Expected policy (this host)

- logind: **lid ignore**
- hypridle: moments of idle → lock / dpms / suspend as configured
- hibernate: only with valid `/swap/swapfile` + resume cmdline

Verify:

```bash
systemd-analyze cat-config systemd/logind.conf | rg -i 'HandleLid|IdleAction|Sleep'
pgrep -a hypridle
test -f ~/.config/hypr/hypridle.conf && rg -n 'listener|timeout|on-timeout|on-resume' ~/.config/hypr/hypridle.conf
swapon --show
cat /proc/cmdline | tr ' ' '\n' | rg 'resume'
./008_healthz.sh
```

## Lid suspends immediately / twice

Cause: logind still on `suspend` **and/or** hypridle also sleeps.

Fix logind drop-in (`HandleLidSwitch*=ignore`), reload logind, restart
hypridle. Details: [idle-lock-sleep](../03-session/idle-lock-sleep.md).

## Never sleeps

```bash
systemd-inhibit --list
loginctl session-status
```

Close inhibitors (video playing, ssh with `-o`), check hypridle running, check
for conflicting idle daemons (`swayidle`, noctialia stack).

## Suspend works, hibernate does not

```bash
systemctl hibernate
# if rejected:
journalctl -b -p err | rg -i 'hiber|swap|resume'
```

Work through [swap-hibernate](../02-storage/swap-hibernate.md). Common misses:

- swap ≤ RAM
- missing `resume_offset` after swapfile recreated
- `resume` hook missing from mkinitcpio until rebuild

## Resume to black screen

1. Wait 10s; try `Ctrl+Alt+F3` then back to graphical TTY
2. NVIDIA preserve-memory and services ([nvidia](nvidia.md))
3. hypridle `on-resume` should `hyprctl dispatch dpms on`
4. If image lightly corrupt once: reboot clean; fresh suspend test again

## Sleep then instant wake

```bash
journalctl -b | rg -i 'Wakeup|suspend|ACPI'
cat /proc/acpi/wakeup 2>/dev/null
```

USB devices and NICs can wake; disable selectively in firmware or wakeup
nodes after identifying the culprit.

## Manual tests

```bash
systemctl suspend
systemctl hibernate
loginctl lock-session
hyprlock
```

## If it fails

Capture:

```bash
./008_healthz.sh
./009_nvidia_idle_check.sh
systemd-inhibit --list
journalctl -b -p warning --no-pager | tail -100
```

Restore a known hypridle.conf from backup if recent edits regress behavior.
