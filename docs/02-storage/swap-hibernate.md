# Swap and hibernate

Hibernation writes RAM to a swapfile and powers off. This host uses:

| Setting | Value |
|---------|--------|
| Path | `/swap/swapfile` |
| Size | installed RAM + ~10% buffer |
| Resume | `resume=UUID=…` and `resume_offset=…` on kernel cmdline |
| Hook | `resume` in mkinitcpio `HOOKS` |

Prefer the archinit script over hand-rolled swap on btrfs.

## Inspect current state

```bash
swapon --show
ls -lh /swap/swapfile
grep -E 'swap|/swap' /etc/fstab
cat /proc/cmdline
grep -E 'resume|HOOKS' /etc/mkinitcpio.conf
free -h
```

Size must be **strictly greater than RAM** (script targets ≈ 110%).

## Create or repair with archinit

Script refuses to run if any swap is already active or if `/swap/swapfile`
already exists. Read the script before re-running on a half-configured machine.

```bash
cd /path/to/archinit
./setup_hibernate_swap.sh --dry-run
./setup_hibernate_swap.sh
```

It will:

1. Detect root FS (btrfs / ext4 / xfs)
2. Create `/swap` and a correctly sized swapfile (`btrfs filesystem mkswapfile`
   on btrfs)
3. Derive `resume_offset`
4. Add fstab swap entry
5. Update `/etc/kernel/cmdline` with `resume=` + `resume_offset=`
6. Ensure mkinitcpio `resume` hook
7. Rebuild initramfs/UKI artifacts

Reboot after a successful configure before trusting hibernate.

## Btrfs resume offset (manual check)

```bash
sudo btrfs inspect-internal map-swapfile -r /swap/swapfile
```

Compare to `/proc/cmdline`.

## Test suspend first

Suspend is less commitment than hibernate:

```bash
systemctl suspend
```

Also test the lid path after hypridle is correct
([idle-lock-sleep](../03-session/idle-lock-sleep.md)).

## Test hibernate

1. Save all work; expect a full power-off cycle
2. Confirm swap active and larger than RAM
3. Confirm cmdline has `resume=` and `resume_offset=`
4. Run:

```bash
systemctl hibernate
```

5. Power on; firmware should resume without a clean cold boot wipe of the
   session

On hybrid NVIDIA systems, fix DRM/services first
([NVIDIA](../06-troubleshooting/nvidia.md)).

## Abort / recover from bad resume

- If resume hangs: hard power off, boot normally (session discarded)
- If you loop on a broken resume image: from firmware boot menu pick an entry
  **without** valid resume, or from recovery strip resume params temporarily,
  boot, disable hibernate, fix swap/offset, rebuild UKI
- Do not shrink or defrag a hibernate swapfile under the feet of a hibernated
  image

## What not to do

- Do not use a swapfile smaller than RAM for hibernate
- Do not put the only swapfile inside a path that snapper nukes without
  understanding offsets
- Do not assume ext4 `filefrag` instructions apply unchanged to btrfs —
  use `mkswapfile` / the script

## If it fails

- `hibernate not supported` → no adequate swap or logind sleep config
- Black screen after resume → GPU/NVIDIA preserve-memory, or wrong
  resume_offset after file moved
- Script dies "active swap already exists" → inspect and disable old swap
  deliberately before re-run

Also run:

```bash
./healthz.sh
```
