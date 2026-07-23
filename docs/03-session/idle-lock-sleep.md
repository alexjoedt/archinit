# Idle, lock, and sleep ownership

On this laptop, **hypridle + hyprlock** own idle, screen power, lock, and
(via config) suspend/hibernate entry. **logind must ignore the lid** so you do
not get double-suspend or fights between two policies.

## Intended stack

| Piece | Path / unit | Role |
|-------|-------------|------|
| hypridle | `~/.config/hypr/hypridle.conf` + package `hypridle` | timeouts, dpms, lock, sleep |
| hyprlock | `~/.config/hypr/hyprlock.conf` + package `hyprlock` | screen lock |
| logind | `/etc/systemd/logind.conf` and `logind.conf.d/*.conf` | lid → **ignore** |

Reject conflicting stacks. Presence of `~/.config/noctialia/` is treated as a
**FAIL** by `008_healthz.sh`. Prefer not running `swayidle` in parallel.

## Verify packages and configs

```bash
pacman -Q hypridle hyprlock
test -f ~/.config/hypr/hypridle.conf && echo ok idle
test -f ~/.config/hypr/hyprlock.conf && echo ok lock
test ! -e ~/.config/noctialia && echo ok no noctialia
pgrep -a hypridle
pgrep -a hyprlock
```

## logind lid policy (required)

Effective values must be:

- `HandleLidSwitch=ignore`
- `HandleLidSwitchExternalPower=ignore`
- `HandleLidSwitchDocked=ignore`

```bash
systemd-analyze cat-config systemd/logind.conf | rg -i 'HandleLid'
```

Drop-in example (adjust filename):

```bash
sudo mkdir -p /etc/systemd/logind.conf.d
sudo tee /etc/systemd/logind.conf.d/99-lid-ignore.conf <<'EOF'
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
EOF
sudo systemctl kill -s HUP systemd-logind
# or reboot; SIGHUP reloads logind config on modern systemd
```

Confirm again with `systemd-analyze cat-config`.

## hypridle expectations

Read your `hypridle.conf`. Typical listeners:

- dim / `dpms off` after idle
- `hyprlock` before sleep
- `systemctl suspend` or hibernate on long idle (your choice)
- **on-resume**: `hyprctl dispatch dpms on` (especially important on NVIDIA)

After editing hypridle, restart the process (however you start it — exec-once
in Hyprland, user unit, etc.).

## Manual lock and sleep

```bash
hyprlock
loginctl lock-session
systemctl suspend
systemctl hibernate    # only if [swap-hibernate](../02-storage/swap-hibernate.md) is sound
```

## Inhibitors and double-sleep debug

```bash
systemd-inhibit --list
./008_healthz.sh
# from repo root
```

Symptoms and deeper recipes:
[logind-sleep troubleshooting](../06-troubleshooting/logind-sleep.md).

## NVIDIA note

Suspend/resume black screens often need:

- `nvidia_drm.modeset=1` and often `nvidia_drm.fbdev=1`
- `NVreg_PreserveVideoMemoryAllocations=1`
- `nvidia-suspend.service`, `nvidia-hibernate.service`, `nvidia-resume.service` enabled

Run `./009_nvidia_idle_check.sh` from the repo. Full page:
[NVIDIA](../06-troubleshooting/nvidia.md).

## If it fails

| Symptom | Check |
|---------|--------|
| Lid always suspends immediately | logind still `suspend` |
| Suspends twice / wakes weirdly | both logind and hypridle sleeping |
| Never locks | hypridle not running / wrong paths |
| Black after wake | dpms on-resume; NVIDIA preserve memory |
| healthz FAIL noctialia | remove or migrate that config tree |
