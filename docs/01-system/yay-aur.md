# yay and the AUR

Build and install packages from the Arch User Repository. Prefer official
packages first ([pacman](pacman.md)). archinit expects **yay** (or **paru**).

## Install yay (bootstrap)

Needs `base-devel` and `git` (both in `base.txt`).

```bash
sudo pacman -S --needed base-devel git
cd /tmp
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si
yay --version
```

Or install a binary helper if you already trust that path; for this host, yay
from AUR is the default documentation.

## One-shot install AUR packages from the repo

```bash
cd /path/to/archinit
./install_aur.sh
```

The script lists packages from `aur.txt`, prompts for numbers/ranges, and runs
`yay -S --needed --noconfirm` (or paru).

## Daily commands

| Goal | Command |
|------|---------|
| Search | `yay keyword` or `yay -Ss keyword` |
| Install | `yay -S package` |
| Official + AUR upgrade | `yay -Syu` |
| Clean build cache | `yay -Sc` |
| Remove | `yay -Rns package` |
| Info | `yay -Si package` |
| Own package devel info | `yay -Qi package` |

List installed AUR packages:

```bash
pacman -Qm
```

## Review before you build

AUR packages run local build scripts as your user (and install as root via
pacman). Before first install of something untrusted:

1. Open the AUR page or `~/.cache/yay/package/PKGBUILD`
2. Skim `source=`, `prepare()`, `build()`, `package()` for curl|bash or odd paths
3. Prefer packages with recent updates and clear maintainers

## Hygiene

```bash
yay -Yc                 # remove unneeded deps (confirm prompts)
yay -Sc                 # clean caches
du -sh ~/.cache/yay
```

Development packages (`*-git`) rebuild often; pin only what you need (this
repo lists `wezterm-git` and walker/elephant stack in `aur.txt`).

## If it fails

- `makepkg` missing deps → install `base-devel`; re-run with network
- PGP / signature errors → fetch keys only from documented maintainer docs;
  do not blindly `--skippgpcheck` as habit
- Build breaks after `-Syu` → rebuild AUR packages (`yay -S package` or
  `yay -Syu` again) once official libs moved
- No helper found → `install_aur.sh` dies until yay/paru exists
