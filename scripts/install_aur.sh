#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUR_PACKAGES_FILE="${SCRIPT_DIR}/config/packages/aur.txt"

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

pkg_read_list() {
  local file="${1:?file required}"
  grep -v '^\s*#' "$file" | grep -v '^\s*$' | awk '{print $1}'
}

choose_helper() {
  if command -v yay >/dev/null 2>&1; then
    printf 'yay\n'
    return 0
  fi

  if command -v paru >/dev/null 2>&1; then
    printf 'paru\n'
    return 0
  fi

  die "no AUR helper found; install yay or paru first"
}

print_packages() {
  local -n packages_ref="$1"
  local i

  printf '\nAvailable AUR packages from %s:\n\n' "$AUR_PACKAGES_FILE"
  for i in "${!packages_ref[@]}"; do
    printf '  %2d) %s\n' "$((i + 1))" "${packages_ref[$i]}"
  done
  printf '\n'
}

parse_selection() {
  local input="$1"
  local total="$2"
  local part start end idx

  input="${input//,/ }"
  for part in $input; do
    case "$part" in
      *-*)
        start="${part%-*}"
        end="${part#*-}"
        [[ $start =~ ^[0-9]+$ && $end =~ ^[0-9]+$ ]] || return 1
        (( start >= 1 && end >= start && end <= total )) || return 1
        for ((idx = start; idx <= end; idx++)); do
          printf '%s\n' "$idx"
        done
        ;;
      *)
        [[ $part =~ ^[0-9]+$ ]] || return 1
        (( part >= 1 && part <= total )) || return 1
        printf '%s\n' "$part"
        ;;
    esac
  done
}

dedupe_selection() {
  local -a indexes_ref=("$@")
  local -A seen=()
  local -a unique=()
  local idx

  for idx in "${indexes_ref[@]}"; do
    if [[ -z ${seen[$idx]+x} ]]; then
      seen[$idx]=1
      unique+=("$idx")
    fi
  done

  printf '%s\n' "${unique[@]}"
}

install_selected_packages() {
  local helper="$1"
  shift
  local -a selected_packages=("$@")

  log_info "Installing ${#selected_packages[@]} selected package(s) via ${helper}"
  if [[ $helper == "yay" ]]; then
    yay -S --needed --noconfirm -- "${selected_packages[@]}"
  else
    paru -S --needed --noconfirm -- "${selected_packages[@]}"
  fi
}

main() {
  local helper selection
  local -a packages indexes

  require_cmd awk
  require_cmd grep
  [[ -f "$AUR_PACKAGES_FILE" ]] || die "package file not found: ${AUR_PACKAGES_FILE}"

  mapfile -t packages < <(pkg_read_list "$AUR_PACKAGES_FILE")
  [[ ${#packages[@]} -gt 0 ]] || die "no AUR packages found in ${AUR_PACKAGES_FILE}"

  helper="$(choose_helper)"

  print_packages packages

  printf 'Select packages to install by number (examples: 1 3 5-7 or 2,4,6): '
  read -r selection

  [[ -n $selection ]] || die "no packages selected"

  if ! selection_output="$(parse_selection "$selection" "${#packages[@]}")"; then
    die "invalid selection; use numbers or ranges within 1-${#packages[@]}"
  fi

  mapfile -t indexes <<<"$selection_output"
  [[ ${#indexes[@]} -gt 0 ]] || die "no packages selected"

  mapfile -t indexes < <(dedupe_selection "${indexes[@]}")
  local -a selected_packages=()
  local idx
  for idx in "${indexes[@]}"; do
    selected_packages+=("${packages[$((idx - 1))]}")
  done

  install_selected_packages "$helper" "${selected_packages[@]}"
  log_ok "Selected AUR packages installed"
}

main "$@"
