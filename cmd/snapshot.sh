#!/usr/bin/env bash
# cmd/snapshot.sh — capture and list package snapshots

# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_LOG:-} ]] || source "${ARCHINIT_HOME}/lib/log.sh"
# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_SNAPSHOT:-} ]] || source "${ARCHINIT_HOME}/lib/snapshot.sh"

cmd_snapshot_help() {
  cat <<'EOF'
Usage: archinit snapshot [create|list|show [NAME]]

Subcommands:
  create         Capture current explicitly-installed packages to a timestamped
                 snapshot under ~/.local/state/archinit/snapshots/ (default)
  list           List existing snapshots (newest first)
  show [NAME]    Print contents of the given snapshot, or 'latest' if omitted

Options:
  --dry-run      Print what would happen without writing files
EOF
}

cmd_snapshot() {
  local subcmd="${1:-create}"
  shift || true

  case "$subcmd" in
    create)
      log_init
      snapshot_create
      ;;
    list)
      snapshot_list
      ;;
    show)
      local name="${1:-latest}"
      local snap_dir="${ARCHINIT_STATE}/snapshots"

      if [[ $name == "latest" ]]; then
        name="$(snapshot_latest)"
        [[ -z $name ]] && die "No snapshots found. Run 'archinit snapshot' first."
      fi

      local dir="${snap_dir}/${name}"
      [[ -d $dir ]] || die "Snapshot not found: ${name}"

      echo "=== Snapshot: ${name} ==="
      echo "--- native (pacman official) ---"
      cat "${dir}/native.txt" 2>/dev/null || echo "(empty)"
      echo ""
      echo "--- foreign (AUR) ---"
      cat "${dir}/foreign.txt" 2>/dev/null || echo "(empty)"
      ;;
    --help | -h)
      cmd_snapshot_help
      ;;
    *)
      echo "archinit snapshot: unknown subcommand: ${subcmd}" >&2
      cmd_snapshot_help >&2
      return 1
      ;;
  esac
}
