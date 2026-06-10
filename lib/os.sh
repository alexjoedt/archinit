#!/usr/bin/env bash
# lib/os.sh — Arch Linux + tool detection helpers
# Requires: lib/core.sh sourced first.

[[ -n ${_ARCHINIT_OS:-} ]] && return 0
_ARCHINIT_OS=1

# assert_arch — die unless running on Arch Linux
assert_arch() {
  local id
  # shellcheck source=/dev/null
  id="$(
    . /etc/os-release 2>/dev/null
    echo "${ID:-}"
  )"
  [[ $id == "arch" ]] || die "archinit requires Arch Linux (detected: '${id:-unknown}')"
}

# has_cmd CMD — return 0 if CMD is on PATH
has_cmd() {
  command -v "$1" &>/dev/null
}

# pkg_is_installed PKG — return 0 if pacman knows the package is installed
pkg_is_installed() {
  pacman -Qi "$1" &>/dev/null
}

# aur_helper — print the name of the first available AUR helper, or empty
aur_helper() {
  local helper
  for helper in yay paru; do
    if has_cmd "$helper"; then
      echo "$helper"
      return 0
    fi
  done
  echo ""
}

# has_aur_helper — return 0 if any AUR helper is available
has_aur_helper() {
  [[ -n "$(aur_helper)" ]]
}
