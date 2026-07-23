# Backups

archinit installs **restic** and **rsync** (`base.txt`) but does not dictate a
single offline target. Treat backups as complementary to snapper:

| Layer | Restores | Does not replace |
|-------|----------|------------------|
| snapper on root | System files after bad upgrade | Hardware death, theft, offline history |
| restic/rsync | Home + selected system state to other disks/hosts | Instant filesystem rollback speed |

## Prefer order

1. For "upgrade broke `/`": snapper rollback first
2. For deleted photos / laptop loss: restic (or rsync) restore
3. ISO + reinstall only after snapshots and backups fail

## restic sketch (host-local template)

Do **not** commit repository passwords. Example shape only — fill endpoints
yourself:

```bash
export RESTIC_REPOSITORY='/path/to/repo'   # or sftp:… / rest:…
export RESTIC_PASSWORD_FILE="$HOME/.config/restic/password"  # mode 0600

restic version
restic snapshots
restic backup "$HOME" \
  --exclude "$HOME/.cache" \
  --exclude "$HOME/**/node_modules" \
  --exclude "$HOME/.local/share/Trash"
restic check
```

Forget policy example (adjust):

```bash
restic forget --prune --keep-daily 7 --keep-weekly 4 --keep-monthly 6
```

## rsync sketch

```bash
rsync -aHAX --info=progress2 \
  --exclude '.cache' \
  "$HOME/" /mnt/backup/home/
```

Prefer trailing slashes carefully. Test with `--dry-run` first.

## What to include

- `$HOME` less caches
- Dotfiles not already in a public git remote
- `/etc` selectively if you leave stock configs unmanaged (or maintain a
  private etckeeper-style repo)
- Documents outside home if any

## What to skip or handle separately

- `/swap/swapfile`
- VM disks you already snapshot elsewhere
- Cloud-synced dirs you truly trust (still keep one offline copy)

## Restore drill

Schedule a restore test after first successful backup:

```bash
restic restore latest --target /tmp/restore-test --include /home/USER/important-file
```

## If it fails

- Locked repo → `restic unlock` only if no other backup runs
- Permission errors → run as the user that owns the files; avoid root-home mixes
- Empty restic repo password forgotten → unrecoverable; store password in a
  manager, not only memory
