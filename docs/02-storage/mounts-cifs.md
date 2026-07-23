# Network mounts (CIFS/SMB)

Mount Windows/Samba shares for temporary use or permanently via fstab /
systemd automount. Keep credentials out of git and out of this wiki.

## One-shot mount

Install tools if needed:

```bash
sudo pacman -S --needed cifs-utils keyutils
```

```bash
sudo mkdir -p /mnt/share
sudo mount -t cifs //server/share /mnt/share \
  -o username=USER,uid=$(id -u),gid=$(id -g),file_mode=0640,dir_mode=0750,iocharset=utf8
```

Prefer a credentials file over password on the command line:

```bash
# /etc/cred/myshare  (root:root, mode 0600) — example structure only
username=myuser
password=...
domain=OPTIONAL
```

```bash
sudo mount -t cifs //server/share /mnt/share \
  -o credentials=/etc/cred/myshare,uid=$(id -u),gid=$(id -g),file_mode=0640,dir_mode=0750
```

Unmount:

```bash
sudo umount /mnt/share
# busy:
sudo umount -l /mnt/share   # lazy; fix open file handles afterward
```

## Persistent fstab

```fstab
//server/share  /mnt/share  cifs  credentials=/etc/cred/myshare,uid=1000,gid=1000,file_mode=0640,dir_mode=0750,iocharset=utf8,_netdev,nofail  0  0
```

- `_netdev` — wait for network
- `nofail` — do not drop into emergency mode if the NAS is down
- Fix `uid`/`gid` to your user (`id`)

```bash
sudo mount -a
findmnt /mnt/share
```

## systemd automount (idle timeout)

Useful when the NAS should not stay mounted always.

`/etc/systemd/system/mnt-share.mount`:

```ini
[Unit]
Description=NAS share
After=network-online.target
Wants=network-online.target

[Mount]
What=//server/share
Where=/mnt/share
Type=cifs
Options=credentials=/etc/cred/myshare,uid=1000,gid=1000,file_mode=0640,dir_mode=0750,_netdev

[Install]
WantedBy=multi-user.target
```

`/etc/systemd/system/mnt-share.automount`:

```ini
[Unit]
Description=Automount NAS share

[Automount]
Where=/mnt/share
TimeoutIdleSec=300

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now mnt-share.automount
# trigger:
ls /mnt/share
```

## Stale handle / disconnected NAS

```bash
findmnt /mnt/share
sudo umount -f /mnt/share 2>/dev/null || sudo umount -l /mnt/share
sudo systemctl restart mnt-share.automount
```

Application stuck in D-state on a dead mount may require session logout or
reboot if force unmount fails.

## Optional: SSHFS

```bash
sudo pacman -S --needed sshfs
mkdir -p ~/mnt/host
sshfs user@host:/remote/path ~/mnt/host
fusermount3 -u ~/mnt/host
```

## Optional: NFS

```bash
sudo pacman -S --needed nfs-utils
sudo mount -t nfs server:/export /mnt/nfs
```

## If it fails

- `mount error(13)` → credentials / server ACL / dialect (`vers=3.0` etc.)
- `mount error(115)` → network, DNS, firewall, wrong host
- permission denied on files after mount → `uid`/`gid`/`forceuid` options
- hangs at boot → add `nofail` and prefer automount
