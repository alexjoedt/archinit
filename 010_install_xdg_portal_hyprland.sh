#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

BASE_PACKAGES_FILE="base.txt"

log_info() { printf '[INFO] %s\n' "$*"; }
log_ok()   { printf '[ OK ] %s\n' "$*"; }
log_warn() { printf '[WARN] %s\n' "$*"; }
log_error() { printf '[ERR ] %s\n' "$*"; }
die() {
  log_error "$*"
  exit 1
}

require_cmd() {
  local cmd="${1:?command required}"
  command -v "$cmd" >/dev/null 2>&1 || die "required command not found: ${cmd}"
}

is_arch() {
  [[ -f /etc/arch-release ]]
}

as_root() {
  if [[ ${EUID} -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

pkg_read_list() {
  local file="${1:?file required}"
  grep -v '^\s*#' "$file" | grep -v '^\s*$' | awk '{print $1}'
}

pkg_installed() {
  pacman -Q "$1" >/dev/null 2>&1
}

check_base_deps() {
  local -a packages missing
  mapfile -t packages < <(pkg_read_list "$BASE_PACKAGES_FILE")

  [[ ${#packages[@]} -gt 0 ]] || die "no packages found in ${BASE_PACKAGES_FILE}"

  missing=()
  for pkg in "${packages[@]}"; do
    pkg_installed "$pkg" || missing+=("$pkg")
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    log_warn "Missing packages:"
    for pkg in "${missing[@]}"; do
      log_warn "  - ${pkg}"
    done
    die "Install missing packages first (run 001_install_packages.sh)"
  fi

  log_ok "All base packages present"
}

build_portal() {
  local build_dir
  build_dir=$(mktemp -d)
  trap 'rm -rf "$build_dir"' EXIT

  log_info "Cloning xdg-desktop-portal-hyprland into ${build_dir}/src"
  git clone --recursive https://github.com/hyprwm/xdg-desktop-portal-hyprland "${build_dir}/src"

  log_info "Configuring"
  cmake \
    -DCMAKE_INSTALL_LIBEXECDIR=/usr/lib \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -B "${build_dir}/build" \
    -S "${build_dir}/src"

  log_info "Building"
  cmake --build "${build_dir}/build"

  log_info "Installing"
  as_root cmake --install "${build_dir}/build"
}

main() {
  require_cmd awk
  require_cmd grep
  require_cmd pacman
  require_cmd git
  require_cmd cmake

  is_arch || die "This script supports Arch Linux only"
  [[ -f "$BASE_PACKAGES_FILE" ]] || die "Package file not found: ${BASE_PACKAGES_FILE}"

  if [[ ${EUID} -ne 0 ]]; then
    require_cmd sudo
    sudo -v || die "sudo access is required"
  fi

  check_base_deps
  build_portal

  log_ok "xdg-desktop-portal-hyprland installed"
}

main "$@"
