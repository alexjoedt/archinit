# greetd + ReGreet + cage

Wayland-native graphical login stack. Replaces heavier Qt/X11 display managers
(for example SDDM) with:

| Piece | Package | Role |
|-------|---------|------|
| greetd | `greetd` | Login daemon (display manager) |
| ReGreet | `greetd-regreet` | GTK4 greeter UI |
| cage | `cage` | Minimal Wayland compositor that kiosks ReGreet |

Hyprland still starts from a session `.desktop` under
`/usr/share/wayland-sessions/`. greetd only owns the pre-session greeter.

## Disable the old display manager

Stop conflicts on the next boot. Leave the package installed until greetd
works, then remove it if you want.

```bash
sudo systemctl disable sddm.service
# or whatever DM you used: gdm, lightdm, ly, …
```

## Install packages

```bash
sudo pacman -S greetd greetd-regreet cage
```

## Configure greetd

Edit `/etc/greetd/config.toml`:

```toml
[terminal]
# Virtual terminal for the greeter. 1 is the usual DM VT.
vt = 1

[default_session]
# cage runs regreet fullscreen. -s helps multi-monitor setups.
command = "cage -s -- regreet"
user = "greeter"
```

`greeter` is a system user created by the `greetd` package. Do not run the
greeter as your personal account.

## Configure ReGreet

Create `/etc/greetd/regreet.toml` if it does not exist:

```toml
[background]
# Absolute path only. Readable by user greeter.
path = "/usr/share/backgrounds/login-wallpaper.jpg"
fit = "Cover"

[GTK]
# Themes must be installed system-wide (for example under /usr/share/themes).
theme_name = "Adwaita-dark"
icon_theme_name = "Adwaita"
cursor_theme_name = "Adwaita"
font_name = "Cantarell 11"
```

Adjust theme and font names to packages you actually have installed.

### Wallpaper and theme permissions

The greeter runs as `greeter`, not your user. Home paths under `~` are not
readable and often produce a black screen.

Put assets where every user can read them:

```bash
sudo mkdir -p /usr/share/backgrounds
sudo cp /path/to/image.jpg /usr/share/backgrounds/login-wallpaper.jpg
sudo chmod 644 /usr/share/backgrounds/login-wallpaper.jpg
```

GTK themes and icons must also live in system locations (`/usr/share/themes`,
`/usr/share/icons`), not only under `~/.themes`.

## Wayland sessions

ReGreet lists sessions from desktop files:

```bash
ls /usr/share/wayland-sessions/
# expect hyprland.desktop when Hyprland is installed
```

X11 sessions (if any) come from `/usr/share/xsessions/`.

## Enable and reboot

```bash
sudo systemctl enable greetd.service
reboot
```

After login you should land in the session you picked (Hyprland). Confirm:

```bash
echo "$XDG_SESSION_TYPE" "$XDG_CURRENT_DESKTOP"
loginctl show-session "$XDG_SESSION_ID" -p Type -p Desktop -p Class
```

Expect `Type=wayland` for Hyprland.

## Verify units and logs

```bash
systemctl status greetd.service
journalctl -u greetd -b --no-pager
pacman -Q greetd greetd-regreet cage
```

## Fallback if the greeter is black or broken

1. Switch to a text TTY: `Ctrl+Alt+F3`
2. Log in as your user or root
3. Restore the previous DM or drop to TTY-only boot:

```bash
sudo systemctl disable greetd.service
sudo systemctl enable sddm.service   # or your previous DM
sudo reboot
```

Common causes:

| Symptom | Check |
|---------|--------|
| Black screen | Wallpaper path; mode bits (`644`); greeter user can read it |
| Greeter crashes | `journalctl -u greetd -b`; typos in `config.toml` / `regreet.toml` |
| No Hyprland in list | `/usr/share/wayland-sessions/hyprland.desktop` missing |
| Multi-monitor glitch | Keep `cage -s` in the greetd command |

## Optional cleanup

When greetd is stable:

```bash
sudo pacman -Rns sddm   # only if nothing else needs it
```

## Relation to the rest of the session stack

- greeter → pick session → Hyprland starts → [hyprland](hyprland.md)
- After login, idle/lock/sleep stay with hypridle/hyprlock —
  [idle-lock-sleep](idle-lock-sleep.md)
- Session inspection: [loginctl](loginctl.md)
- Boot fails earlier than the greeter: [boot and login](../06-troubleshooting/boot-and-login.md)

## Upstream

- [Arch Wiki: greetd](https://wiki.archlinux.org/title/Greetd)
- [ReGreet](https://github.com/rharish101/ReGreet)
- [cage](https://github.com/Hjdskes/cage)
