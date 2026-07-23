# pacman basics

Install, update, and query official packages. For AUR, use [yay](yay-aur.md).

archinit installs the official set from `base.txt` via
`install_packages.sh` in the repo root.

## Update mirrors and system

```bash
sudo pacman -Syu
```

Check what would change without applying:

```bash
checkupdates   # from pacman-contrib
```

## Install and remove

```bash
sudo pacman -S package
sudo pacman -S --needed package another   # skip if already up to date
sudo pacman -Rns package                  # remove package + unused deps
```

`--needed` is what `install_packages.sh` uses.

Install everything listed in the repo:

```bash
cd /path/to/archinit
./install_packages.sh
```

## Query packages

| Goal | Command |
|------|---------|
| Is it installed? | `pacman -Q package` |
| Explicitly installed | `pacman -Qe` |
| Orphans | `pacman -Qdt` |
| Search remote | `pacman -Ss keyword` |
| Search local | `pacman -Qs keyword` |
| Package info | `pacman -Si package` / `pacman -Qi package` |
| Files owned by package | `pacman -Ql package` |
| Which package owns a file? | `pacman -Qo /usr/bin/foo` |
| Files in remote package | `pacman -Fl package` (after `-Fy`) |
| Update file DB | `sudo pacman -Fy` |

List only official packages that are outdated:

```bash
pacman -Qu
```

## Cache and disk

```bash
du -sh /var/cache/pacman/pkg
sudo paccache -r          # keep last 3 versions (pacman-contrib)
sudo pacman -Sc           # interactive cache clean
sudo pacman -Scc          # aggressive; you re-download everything later
```

## Keyring and database problems

```bash
sudo pacman -Sy archlinux-keyring && sudo pacman -Su
sudo pacman-key --init
sudo pacman-key --populate archlinux
```

If a transaction was interrupted:

```bash
sudo rm -f /var/lib/pacman/db.lck
sudo pacman -Syu
```

## Snapshots around pacman

snap-pac creates pre/post snapper snapshots for pacman transactions when
configured. Confirm:

```bash
pacman -Q snap-pac snapper
snapper list
```

See [snapper](../02-storage/snapper.md) and [updates](../05-ops/updates.md).

## Official vs AUR vs random repos

- **Official** (`core`, `extra`, …): prefer these first
- **AUR**: user-produced PKGBUILDs; review before build ([yay](yay-aur.md))
- **Unofficial binary repos**: only if you consciously add them and trust them

Do not install the same package name from conflicting sources.

## If it fails

- Conflicting files → read the error; `pacman -Qo` on the path; fix ownership
  or remove the stray file intentionally
- Mirror 404 / slow → refresh mirrorlist, then `-Syu`
- Broken after upgrade → snapper rollback, then [boot recovery](../06-troubleshooting/boot-and-login.md)
