#!/usr/bin/env bash
# scripts/enable_user_services.sh

set -euo pipefail
IFS=$'\n\t'

# ---

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCHINIT_HOME="${ARCHINIT_HOME:-$(cd "${_SCRIPT_DIR}/.." && pwd)}"
export ARCHINIT_HOME

DRY_RUN="${DRY_RUN:-0}"
ASSUME_YES="${ASSUME_YES:-0}"
VERBOSE="${VERBOSE:-0}"
QUIET="${QUIET:-0}"
NO_COLOR="${NO_COLOR:-0}"

# ---

if [[ -t 2 && "$NO_COLOR" -ne 1 ]]; then
  _C_INFO=$'\033[36m'
  _C_OK=$'\033[32m'
  _C_WARN=$'\033[33m'
  _C_ERROR=$'\033[31m'
  _C_RESET=$'\033[0m'
else
  _C_INFO=""
  _C_OK=""
  _C_WARN=""
  _C_ERROR=""
  _C_RESET=""
fi

log_info() { [[ "$QUIET" -eq 1 ]] || printf '%s[INFO]%s %s\n' "$_C_INFO" "$_C_RESET" "$*" >&2; }
log_ok() { [[ "$QUIET" -eq 1 ]] || printf '%s[ OK ]%s %s\n' "$_C_OK" "$_C_RESET" "$*" >&2; }
log_warn() { printf '%s[WARN]%s %s\n' "$_C_WARN" "$_C_RESET" "$*" >&2; }
log_error() { printf '%s[ERR ]%s %s\n' "$_C_ERROR" "$_C_RESET" "$*" >&2; }

die() {
  log_error "$*"
  exit 1
}

require_cmd() {
  local cmd="${1:?command required}"
  local msg="${2:-required command not found: ${cmd}}"
  command -v "$cmd" >/dev/null 2>&1 || die "$msg"
}

# run <command> [args...]
# Executes a command, honoring DRY_RUN and VERBOSE.
run() {
  if [[ "$VERBOSE" -eq 1 || "$DRY_RUN" -eq 1 ]]; then
    local IFS=' '
    log_info "+ $*"
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    return 0
  fi

  "$@"
}

# ui_choose_multi <prompt> <item...>
# Prints one selected item per line to stdout.
ui_choose_multi() {
  local prompt="$1"
  shift
  local -a items=("$@")
  local -a chosen=()
  local i reply

  if [[ "$ASSUME_YES" -eq 1 ]]; then
    printf '%s\n' "${items[@]}"
    return 0
  fi

  {
    printf '%s\n' "$prompt"
    for i in "${!items[@]}"; do
      printf '  %2d) %s\n' "$((i + 1))" "${items[$i]}"
    done
    printf 'Enter numbers (space/comma separated), "all", or empty to skip: '
  } >&2

  read -r reply

  reply="${reply//,/ }"
  if [[ -z "$reply" ]]; then
    return 0
  fi

  if [[ "$reply" == "all" ]]; then
    printf '%s\n' "${items[@]}"
    return 0
  fi

  local n
  for n in $reply; do
    if [[ "$n" =~ ^[0-9]+$ ]] && ((n >= 1 && n <= ${#items[@]})); then
      chosen+=("${items[$((n - 1))]}")
    else
      log_warn "Ignoring invalid selection: ${n}"
    fi
  done

  [[ ${#chosen[@]} -gt 0 ]] && printf '%s\n' "${chosen[@]}"
  return 0
}

help() {
  cat <<'EOF'
Usage: enable_user_services.sh

Lists all user service units found in:
  - ~/.config/systemd
  - ~/.config/systemd/user

Lets you choose which services to enable, then enables and starts them with:
  systemctl --user enable --now <unit>

Respects ARCHINIT flags when set:
  DRY_RUN=1 ASSUME_YES=1 VERBOSE=1 QUIET=1 NO_COLOR=1
EOF
}

# ---

collect_units() {
  local -a search_dirs=(
    "$HOME/.config/systemd"
    "$HOME/.config/systemd/user"
  )

  local -A seen=()
  local dir file unit

  for dir in "${search_dirs[@]}"; do
    [[ -d "$dir" ]] || continue
    while IFS= read -r -d '' file; do
      unit="$(basename "$file")"
      # Template units require explicit instance names and are skipped.
      [[ "$unit" == *@.service ]] && continue
      seen["$unit"]=1
    done < <(find "$dir" -type f -name '*.service' -print0)
  done

  if [[ ${#seen[@]} -eq 0 ]]; then
    return 0
  fi

  printf '%s\n' "${!seen[@]}" | sort
}

print_service_table() {
  local unit enabled active

  printf '%-40s %-12s %-12s\n' "SERVICE" "ENABLED" "ACTIVE"
  printf '%-40s %-12s %-12s\n' "-------" "-------" "------"

  for unit in "$@"; do
    enabled="$(systemctl --user is-enabled "$unit" 2>/dev/null || true)"
    active="$(systemctl --user is-active "$unit" 2>/dev/null || true)"
    [[ -n "$enabled" ]] || enabled="unknown"
    [[ -n "$active" ]] || active="unknown"
    printf '%-40s %-12s %-12s\n' "$unit" "$enabled" "$active"
  done
}

enable_selected_units() {
  local -a selected_units=("$@")
  local unit
  local failed=0

  run systemctl --user daemon-reload

  for unit in "${selected_units[@]}"; do
    log_info "Enabling and starting ${unit}"
    if run systemctl --user enable --now "$unit"; then
      log_ok "Enabled and started ${unit}"
    else
      log_error "Failed to enable/start ${unit}"
      failed=1
    fi
  done

  return "$failed"
}

main() {
  if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
    help
    exit 0
  fi

  require_cmd systemctl "systemctl is required"

  local -a units=()
  local -a selected_units=()
  local selected_raw

  mapfile -t units < <(collect_units)

  if [[ ${#units[@]} -eq 0 ]]; then
    log_warn "No user .service files found in ~/.config/systemd or ~/.config/systemd/user"
    exit 0
  fi

  log_info "Discovered ${#units[@]} user service file(s):"
  print_service_table "${units[@]}"

  selected_raw="$(ui_choose_multi "Select user services to enable and start" "${units[@]}")"
  if [[ -z "$selected_raw" ]]; then
    log_warn "No services selected. Nothing to do."
    exit 0
  fi

  mapfile -t selected_units <<<"$selected_raw"

  log_info "Selected ${#selected_units[@]} service(s)."
  if enable_selected_units "${selected_units[@]}"; then
    log_ok "All selected services are enabled and started."
  else
    die "One or more services failed to enable/start"
  fi
}

main "$@"
