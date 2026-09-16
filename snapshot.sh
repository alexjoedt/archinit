#!/usr/bin/env bash
#
# Snapshot explicitly installed native pacman packages into snapshot.txt.
# Packages known from base.txt keep their category header; everything else
# lands under "# Uncategorized". Prints a diff against base.txt afterwards.

set -euo pipefail
IFS=$'\n\t'

BASE_PACKAGES_FILE="base.txt"
SNAPSHOT_FILE="snapshot.txt"
UNCATEGORIZED_HEADER="# Uncategorized"

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

# Emits "<header>\t<package>" per package line in base.txt, in file order.
# Header is the last "# ..." line seen; packages before any header get an
# empty header. Commented-out packages ("# mako # reason") are not headers
# and are dropped, as are duplicates.
read_base_categories() {
  local file="${1:?file required}"
  awk '
    /^[[:space:]]*#[[:space:]]*[a-z0-9@._+-]+[[:space:]]*(#.*)?$/ { next }
    /^[[:space:]]*#/ { header = $0; sub(/^[[:space:]]+/, "", header); next }
    /^[[:space:]]*$/ { next }
    { pkg = $1; if (!(pkg in seen)) { seen[pkg] = 1; print header "\t" pkg } }
  ' "$file"
}

print_list() {
  local title="${1:?title required}"
  shift
  [[ $# -gt 0 ]] || return 0
  printf '\n%s (%d):\n' "$title" "$#"
  printf '  %s\n' "$@"
}

main() {
  require_cmd awk
  require_cmd comm
  require_cmd pacman

  is_arch || die "This script supports Arch Linux only"
  [[ -f "$BASE_PACKAGES_FILE" ]] || die "Package file not found: ${BASE_PACKAGES_FILE}"

  local -a explicit installed
  mapfile -t explicit < <(pacman -Qenq | sort -u)
  mapfile -t installed < <(pacman -Qq | sort -u)
  [[ ${#explicit[@]} -gt 0 ]] || die "pacman returned no explicitly installed packages"

  local -A is_explicit is_installed in_base
  local pkg
  for pkg in "${explicit[@]}"; do is_explicit["$pkg"]=1; done
  for pkg in "${installed[@]}"; do is_installed["$pkg"]=1; done

  # Walk base.txt in order and collect installed packages per header.
  local -a headers=()
  local -A section_pkgs=()
  local -a missing=() dep_only=()
  local header line current=""
  while IFS=$'\t' read -r header pkg; do
    in_base["$pkg"]=1
    if [[ "$header" != "$current" || ${#headers[@]} -eq 0 ]]; then
      current="$header"
      headers+=("$header")
    fi
    if [[ -n ${is_explicit["$pkg"]:-} ]]; then
      section_pkgs["$header"]+="${pkg}"$'\n'
    elif [[ -n ${is_installed["$pkg"]:-} ]]; then
      dep_only+=("$pkg")
    else
      missing+=("$pkg")
    fi
  done < <(read_base_categories "$BASE_PACKAGES_FILE")

  local -a new=()
  for pkg in "${explicit[@]}"; do
    [[ -n ${in_base["$pkg"]:-} ]] || new+=("$pkg")
  done

  {
    printf '# Snapshot %s on %s (%d explicit native packages)\n' \
      "$(date +%F)" "$(uname -n)" "${#explicit[@]}"
    for header in "${headers[@]}"; do
      [[ -n ${section_pkgs["$header"]:-} ]] || continue
      printf '\n%s\n' "${header:-# Untitled}"
      printf '%s' "${section_pkgs["$header"]}"
    done
    if [[ ${#new[@]} -gt 0 ]]; then
      printf '\n%s\n' "$UNCATEGORIZED_HEADER"
      printf '%s\n' "${new[@]}"
    fi
  } >"$SNAPSHOT_FILE"

  log_ok "Wrote ${#explicit[@]} packages to ${SNAPSHOT_FILE}"

  print_list "New (installed, not in ${BASE_PACKAGES_FILE})" "${new[@]}"
  print_list "Missing (in ${BASE_PACKAGES_FILE}, not installed)" "${missing[@]}"
  print_list "Dependency only (in ${BASE_PACKAGES_FILE}, installed but not explicit)" "${dep_only[@]}"
}

main "$@"
