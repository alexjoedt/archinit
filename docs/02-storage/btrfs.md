# btrfs

Root is expected to be **btrfs**. Snapshots (snapper) and layout awareness
matter before hibernation swap and big balances.

## Confirm root

```bash
findmnt -no FSTYPE,SOURCE,OPTIONS /
findmnt -no UUID /
btrfs filesystem show
btrfs filesystem df /
```

If FSTYPE is not `btrfs`, this baseline (snapper + archinit healthz) does not
apply as written.

## Subvolumes and mounts

```bash
sudo btrfs subvolume list /
findmnt -t btrfs
cat /etc/fstab
```

Note which subvolume is mounted at `/` (`subvol=` or `subvolid=`). Snapper
rollback and chroot recovery depend on that layout.

Common patterns (yours may differ — verify on hardware):

- `@` → `/`
- `@home` → `/home`
- separate subvolume or directory for `/swap`

## Space and health

```bash
sudo btrfs filesystem usage /
sudo btrfs device stats /
sudo btrfs scrub status /
```

Optional scrub (IO heavy):

```bash
sudo btrfs scrub start /
sudo btrfs scrub status -d /
```

## Balance (light touch)

Do not free-space balance casually on SSDs without reading upstream guidance.
If you must:

```bash
sudo btrfs balance status /
# filtered balances only after you know why
```

Prefer `snapper cleanup` and deleting junk before aggressive balance.

## Swapfile note

Hibernate swap lives at **`/swap/swapfile`**. Prefer a location that is **not**
bundled into root snapshots in a painful way (archinit uses the `/swap/`
prefix for that reason). Create only via
[swap-hibernate](swap-hibernate.md) / `006_setup_hibernate_swap.sh`, not random
`fallocate` on btrfs without `mkswapfile`.

## What not to do

- Do not run `btrfs balance` or `delete` while confused about subvolume ids
- Do not put large ephemeral paths into snapshotted subvolumes without quota
  plan (VMs, build caches) if disk pain becomes recurring
- Do not snapshot a swapfile subvolume if you isolated swap to avoid that

## If it fails

- `No space left` with "apparent" free space → snapshots filling disk;
  [snapper](snapper.md) cleanup
- mount fails after edit of fstab → ISO + mount correct `subvol=`
- scrub errors → backup and investigate before delete
