#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

BASE_PACKAGES_FILE="base.txt"
SNAPSHOT_PACKAGES_FILE="snapshot.txt"
PACKAGES_FILE="$BASE_PACKAGES_FILE"
USE_SNAPSHOT=""  # "yes" | "no" | "" (ask)
MERGED_FILE=""

log_info() { printf '[INFO] %s\n' "$*"; }
log_ok() { printf '[ OK ] %s\n' "$*"; }
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

usage() {
  cat <<EOF
Usage: $0 [--with-snapshot|--no-snapshot]

Installs packages from ${BASE_PACKAGES_FILE}. If ${SNAPSHOT_PACKAGES_FILE}
exists, asks whether to merge it in (union, deduplicated, base first).

  --with-snapshot   merge ${SNAPSHOT_PACKAGES_FILE} without asking
  --no-snapshot     ignore ${SNAPSHOT_PACKAGES_FILE} without asking
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --with-snapshot) USE_SNAPSHOT="yes" ;;
      --no-snapshot) USE_SNAPSHOT="no" ;;
      -h | --help)
        usage
        exit 0
        ;;
      *) die "unknown argument: $1" ;;
    esac
    shift
  done
}

cleanup() {
  [[ -n "$MERGED_FILE" && -f "$MERGED_FILE" ]] && rm -f -- "$MERGED_FILE"
  return 0
}

ask_yes_no() {
  local prompt="${1:?prompt required}" answer
  [[ -t 0 ]] || return 1
  read -r -p "${prompt} [y/N] " answer
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

# Decides whether to use the snapshot and, if so, writes the merged list
# to a temp file and points PACKAGES_FILE at it.
resolve_packages_file() {
  [[ -f "$SNAPSHOT_PACKAGES_FILE" ]] || return 0

  if [[ -z "$USE_SNAPSHOT" ]]; then
    if ask_yes_no "Merge ${SNAPSHOT_PACKAGES_FILE} into the install list?"; then
      USE_SNAPSHOT="yes"
    else
      USE_SNAPSHOT="no"
    fi
  fi

  if [[ "$USE_SNAPSHOT" != "yes" ]]; then
    log_info "Ignoring ${SNAPSHOT_PACKAGES_FILE}"
    return 0
  fi

  local base_count snapshot_count merged_count
  base_count=$(pkg_read_list "$BASE_PACKAGES_FILE" | sort -u | wc -l)
  snapshot_count=$(pkg_read_list "$SNAPSHOT_PACKAGES_FILE" | sort -u | wc -l)

  MERGED_FILE=$(mktemp -t archinit-packages.XXXXXX)
  {
    pkg_read_list "$BASE_PACKAGES_FILE"
    pkg_read_list "$SNAPSHOT_PACKAGES_FILE"
  } | awk '!seen[$0]++' >"$MERGED_FILE"
  merged_count=$(wc -l <"$MERGED_FILE")

  PACKAGES_FILE="$MERGED_FILE"
  log_info "Merged ${BASE_PACKAGES_FILE} (${base_count}) + ${SNAPSHOT_PACKAGES_FILE} (${snapshot_count}) -> ${merged_count} packages in ${MERGED_FILE}"
}

install_base_packages() {
  local -a packages failed
  mapfile -t packages < <(pkg_read_list "$PACKAGES_FILE")

  [[ ${#packages[@]} -gt 0 ]] || die "no packages found in ${PACKAGES_FILE}"

  log_info "Installing ${#packages[@]} packages from ${PACKAGES_FILE}"

  if as_root pacman -S --needed --noconfirm -- "${packages[@]}"; then
    log_ok "Base packages installed"
    return 0
  fi

  log_warn "Batch install failed, retrying one package at a time"
  failed=()

  for pkg in "${packages[@]}"; do
    if as_root pacman -S --needed --noconfirm -- "$pkg"; then
      log_ok "installed: ${pkg}"
    else
      log_warn "failed: ${pkg}"
      failed+=("$pkg")
    fi
  done

  if [[ ${#failed[@]} -gt 0 ]]; then
    log_error "Some packages failed to install: ${failed[*]}"
    return 1
  fi

  log_ok "Base packages installed"
  return 0
}

main() {
  parse_args "$@"
  trap cleanup EXIT

  require_cmd awk
  require_cmd grep
  require_cmd mktemp
  require_cmd pacman

  is_arch || die "This script supports Arch Linux only"
  [[ -f "$BASE_PACKAGES_FILE" ]] || die "Package file not found: ${BASE_PACKAGES_FILE}"

  if [[ ${EUID} -ne 0 ]]; then
    require_cmd sudo
    sudo -v || die "sudo access is required"
  fi

  resolve_packages_file

  if ! install_base_packages; then
    log_warn "Completed with package installation failures"
    exit 1
  fi

  log_ok "All done"
}

main "$@"
