import { defineConfig } from 'vitepress'

// https://vitepress.dev/reference/site-config
export default defineConfig({
  title: 'Arch Hyprland Wiki',
  description:
    'Personal operations wiki for an Arch Linux + Hyprland laptop (archinit).',
  lang: 'en-US',
  cleanUrls: true,
  lastUpdated: true,

  themeConfig: {
    // https://vitepress.dev/reference/default-theme-config
    siteTitle: 'Arch Hyprland Wiki',
    outline: { level: [2, 3] },
    search: {
      provider: 'local',
    },

    nav: [
      { text: 'Home', link: '/' },
      { text: 'Overview', link: '/README' },
      {
        text: 'Sections',
        items: [
          { text: 'System', link: '/01-system/overview' },
          { text: 'Storage', link: '/02-storage/btrfs' },
          { text: 'Session', link: '/03-session/hyprland' },
          { text: 'Desktop', link: '/04-desktop/audio-pipewire' },
          { text: 'Ops', link: '/05-ops/updates' },
          { text: 'Troubleshooting', link: '/06-troubleshooting/boot-and-login' },
          { text: 'Reference', link: '/07-reference/cheatsheet' },
        ],
      },
      { text: 'Cheatsheet', link: '/07-reference/cheatsheet' },
    ],

    sidebar: [
      {
        text: 'Start',
        items: [
          { text: 'Home', link: '/' },
          { text: 'Overview', link: '/README' },
        ],
      },
      {
        text: '01 - System',
        collapsed: false,
        items: [
          { text: 'Overview', link: '/01-system/overview' },
          { text: 'pacman', link: '/01-system/pacman' },
          { text: 'yay / AUR', link: '/01-system/yay-aur' },
          { text: 'systemd', link: '/01-system/systemd' },
          { text: 'Kernels and boot', link: '/01-system/kernels-boot' },
        ],
      },
      {
        text: '02 - Storage',
        collapsed: false,
        items: [
          { text: 'btrfs', link: '/02-storage/btrfs' },
          { text: 'snapper', link: '/02-storage/snapper' },
          { text: 'Swap and hibernate', link: '/02-storage/swap-hibernate' },
          { text: 'CIFS mounts', link: '/02-storage/mounts-cifs' },
        ],
      },
      {
        text: '03 - Session',
        collapsed: false,
        items: [
          { text: 'loginctl', link: '/03-session/loginctl' },
          { text: 'Hyprland', link: '/03-session/hyprland' },
          { text: 'Idle, lock, sleep', link: '/03-session/idle-lock-sleep' },
        ],
      },
      {
        text: '04 - Desktop',
        collapsed: false,
        items: [
          { text: 'PipeWire', link: '/04-desktop/audio-pipewire' },
          { text: 'NetworkManager', link: '/04-desktop/network-nmcli' },
          { text: 'Bluetooth', link: '/04-desktop/bluetooth' },
          { text: 'Portals and screenshots', link: '/04-desktop/portals-screenshare' },
        ],
      },
      {
        text: '05 - Ops',
        collapsed: false,
        items: [
          { text: 'Safe updates', link: '/05-ops/updates' },
          { text: 'Backups', link: '/05-ops/backups' },
          { text: 'Health checks', link: '/05-ops/health-checks' },
        ],
      },
      {
        text: '06 - Troubleshooting',
        collapsed: false,
        items: [
          { text: 'Boot and login', link: '/06-troubleshooting/boot-and-login' },
          { text: 'Hyprland', link: '/06-troubleshooting/hyprland' },
          { text: 'logind and sleep', link: '/06-troubleshooting/logind-sleep' },
          { text: 'Network and audio', link: '/06-troubleshooting/network-audio' },
          { text: 'NVIDIA', link: '/06-troubleshooting/nvidia' },
        ],
      },
      {
        text: '07 - Reference',
        collapsed: false,
        items: [
          { text: 'Cheatsheet', link: '/07-reference/cheatsheet' },
          { text: 'Glossary', link: '/07-reference/glossary' },
          { text: 'Links', link: '/07-reference/links' },
        ],
      },
    ],

    socialLinks: [
      { icon: 'github', link: 'https://github.com/alexjoedt/archinit' },
    ],

    editLink: {
      pattern: 'https://github.com/alexjoedt/archinit/edit/main/docs/:path',
      text: 'Edit this page',
    },

    footer: {
      message: 'Personal Arch + Hyprland ops notes (archinit)',
      copyright: 'Not a substitute for the Arch Wiki',
    },

    docFooter: {
      prev: 'Previous',
      next: 'Next',
    },

    returnToTopLabel: 'Back to top',
    sidebarMenuLabel: 'Menu',
    darkModeSwitchLabel: 'Theme',
    outlineTitle: 'On this page',
  },
})
