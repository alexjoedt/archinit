#!/usr/bin/env bash
# cmd/restore.sh — reinstall packages from a snapshot

# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_LOG:-} ]] || source "${ARCHINIT_HOME}/lib/log.sh"
# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_SNAPSHOT:-} ]] || source "${ARCHINIT_HOME}/lib/snapshot.sh"
# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_UI:-} ]] || source "${ARCHINIT_HOME}/lib/ui.sh"

cmd_restore_help() {
  cat <<'EOF'
Usage: archinit restore [NAME]

Reinstall packages from a snapshot (or 'latest' if NAME is omitted).
Native packages are installed via pacman --needed; AUR packages via yay --needed.
Re-running is idempotent.

Options:
  --dry-run   Print packages that would be installed without installing
  --yes       Skip confirmation prompt
EOF
}

cmd_restore() {
  local name=""

  for arg in "$@"; do
    case "$arg" in
      --help|-h) cmd_restore_help; exit 0 ;;
      --*) ;;
      *) name="$arg" ;;
    esac
  done

  if ! snapshot_exists; then
    die "No snapshots found. Run 'archinit snapshot' first."
  fi

  local snap_name
  if [[ -z $name ]]; then
    snap_name="$(snapshot_latest)"
    [[ -z $snap_name ]] && die "Could not resolve latest snapshot."
  else
    snap_name="$name"
  fi

  if ! ui_confirm "Restore packages from snapshot '${snap_name}'?"; then
    log_info "Aborted."
    return 0
  fi

  log_init
  snapshot_restore "$snap_name"
  log_ok "Restore from snapshot '${snap_name}' complete"
}
