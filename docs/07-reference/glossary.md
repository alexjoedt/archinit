# Glossary

Short definitions as used in this wiki.

## AUR

Arch User Repository. Community PKGBUILDs built locally (via yay). Not
official staff-supported packages.

## ESP

EFI System Partition. FAT filesystem where systemd-boot and UKIs usually
live. `bootctl status` shows the path.

## hibernate vs suspend

- **suspend** (s2idle/S3): RAM powered, fast wake, battery drain
- **hibernate** (S4): RAM image to swap, power off, needs large swap + resume
  wiring

## inhibitor

A claim on the system that delays or blocks idle/sleep (apps via logind).
List with `systemd-inhibit --list`.

## mkinitcpio

Arch tool that builds the initial ramdisk or UKI from hooks and presets.
Hibernate needs the `resume` hook.

## noctialia

Alternate idle/config tree rejected by this host's baseline. If
`~/.config/noctialia/` exists, migrate away to hypridle/hyprlock.

## pacman / yay

pacman manages official packages. yay wraps pacman and builds AUR packages.

## resume / resume_offset

Kernel parameters telling the early boot tree **where** the hibernation image
lives. For a file on a filesystem, UUID alone is not enough — the physical
**offset** of the swapfile is required. Recreate swapfile ⇒ recompute offset.

## seat / session

logind concepts. A **seat** is a set of hardware for local interaction. A
**session** is a user login on a seat (or remote). Hyprland runs in a
graphical session (`Type=wayland`).

## snap-pac

pacman hooks that create snapper pre/post snapshots around package
transactions.

## snapper

Userspace tool for btrfs snapshot management and timelines.

## subvolume

btrfs tree that can be mounted and snapshotted independently (for example
`@` root vs `@home`).

## UKI

Unified Kernel Image. Single EFI binary packing kernel + initramfs + cmdline
(and more). Managed with mkinitcpio presets + systemd-boot on this baseline.

## Wayland / XWayland

Wayland is the display protocol Hyprland implements. XWayland runs legacy X11
clients inside the Wayland session.
