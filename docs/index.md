---
# https://vitepress.dev/reference/default-theme-home-page
layout: home

hero:
  name: Arch Hyprland Wiki
  text: Personal ops notes
  tagline: Arch Linux + Hyprland laptop — procedures for updates, sleep, snapshots, and recovery (archinit).
  actions:
    - theme: brand
      text: Overview
      link: /README
    - theme: alt
      text: Cheatsheet
      link: /07-reference/cheatsheet
    - theme: alt
      text: Troubleshooting
      link: /06-troubleshooting/boot-and-login

features:
  - title: System
    details: pacman, yay/AUR, systemd, linux-lts and UKI boot hygiene.
    link: /01-system/overview
    linkText: System guide
  - title: Storage
    details: btrfs, snapper + snap-pac, hibernate swap at /swap/swapfile, CIFS mounts.
    link: /02-storage/btrfs
    linkText: Storage guide
  - title: Session
    details: greetd/ReGreet, loginctl, Hyprland, hypridle/hyprlock — lid ignored so idle owns sleep.
    link: /03-session/greetd
    linkText: Session guide
  - title: Desktop
    details: PipeWire, NetworkManager, Bluetooth, portals and grim/slurp screenshots.
    link: /04-desktop/audio-pipewire
    linkText: Desktop guide
  - title: Ops
    details: Safe update ritual, restic/rsync notes, healthz and NVIDIA checks.
    link: /05-ops/updates
    linkText: Ops guide
  - title: Troubleshooting
    details: Boot, Hyprland, sleep, network/audio, and NVIDIA failure recipes.
    link: /06-troubleshooting/boot-and-login
    linkText: Fix it
---
