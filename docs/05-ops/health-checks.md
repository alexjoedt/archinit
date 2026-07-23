# Health checks

Read-only audits for this laptop. They exist so you do not discover baseline
drift only after suspend fails on a train.

## healthz.sh (primary)

Spec: `healthz.md` in the repo root. Script: `healthz.sh`.

```bash
cd /path/to/archinit
./healthz.sh
echo $?
```

### Exit codes

| Code | Meaning |
|------|---------|
| `0` | All PASS |
| `1` | At least one WARN, zero FAIL |
| `2` | At least one FAIL |

### Checks (summary)

1. Essential CLI: `jq`, `rg`, `fd` on `PATH`
2. hypridle + hyprlock configs/packages; fail if `~/.config/noctialia/` exists
3. logind lid switches = `ignore`
4. btrfs root + snapper + snap-pac configured; timer soft warnings
5. `/swap/swapfile` sized for hibernate + fstab + resume cmdline/hook

Never mutates the system (no package installs, no `systemctl enable`).

Use after:

- Fresh archinit setup
- Kernel / NVIDIA / sleep stack changes
- Weekly if you want a modest drumbeat

## nvidia_idle_check.sh

German-labelled console diagnostics for Hyprland + NVIDIA DPMS/suspend:

```bash
./nvidia_idle_check.sh
```

Covers:

- `nvidia_drm.modeset=1` / `nvidia_drm.fbdev=1` on cmdline
- `NVreg_PreserveVideoMemoryAllocations=1`
- `nvidia-{suspend,hibernate,resume}.service` enabled
- hypridle.conf presence (hints about `dpms on` resume)

Exit status of this script is informational; fix red ❌ markers.

## Manual quick pulse

```bash
findmnt -no FSTYPE /
swapon --show
bootctl status | head
systemctl --failed
systemctl --user --failed
nmcli general status
wpctl status | head
```

## If healthz fails

| Check area | Fix docs |
|------------|----------|
| CLI tools | [pacman](../01-system/pacman.md) |
| hypr / noctialia conflict | [idle-lock-sleep](../03-session/idle-lock-sleep.md) |
| logind lid | [idle-lock-sleep](../03-session/idle-lock-sleep.md) |
| btrfs/snapper | [btrfs](../02-storage/btrfs.md), [snapper](../02-storage/snapper.md) |
| swap/resume | [swap-hibernate](../02-storage/swap-hibernate.md) |
| NVIDIA | [nvidia](../06-troubleshooting/nvidia.md) |
