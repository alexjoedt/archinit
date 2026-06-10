#!/usr/bin/env bash
# cmd/uninstall.sh — remove archinit (keep installed packages)

# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_LOG:-} ]] || source "${ARCHINIT_HOME}/lib/log.sh"
# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_UI:-} ]] || source "${ARCHINIT_HOME}/lib/ui.sh"

cmd_uninstall_help() {
  cat <<'EOF'
Usage: archinit uninstall [--purge]

Remove archinit from the system:
  - Removes the 'source .../shell/archinit.sh' line from ~/.zshrc and ~/.bashrc
  - Removes ~/.archinit (the git clone / ARCHINIT_HOME)

Installed packages are kept; remove them manually if desired.
XDG state (snapshots, logs) is kept by default.

Options:
  --purge     Also remove $XDG_STATE_HOME/archinit (snapshots, logs, state)
  --dry-run   Print actions without executing
  --yes       Skip confirmation prompt
EOF
}

cmd_uninstall() {
  local purge=0

  for arg in "$@"; do
    case "$arg" in
      --purge) purge=1 ;;
      --help | -h)
        cmd_uninstall_help
        exit 0
        ;;
      --*) ;;
    esac
  done

  local archinit_dir="${ARCHINIT_HOME}"
  local state_dir="${ARCHINIT_STATE}"
  local rc_pattern='source.*archinit.*shell/archinit\.sh'

  echo "archinit uninstall will:"
  echo "  - Remove shell hook from ~/.zshrc and ~/.bashrc"
  echo "  - Remove ${archinit_dir}"
  if ((purge)); then
    echo "  - Remove ${state_dir} (--purge)"
  else
    echo "  - Keep ${state_dir} (snapshots/logs preserved)"
  fi
  echo "  - Installed packages will NOT be removed"
  echo ""

  if ! ui_confirm "Proceed with uninstall?"; then
    log_info "Aborted."
    return 0
  fi

  # Remove shell hook lines
  local rc_file
  for rc_file in "${HOME}/.zshrc" "${HOME}/.bashrc"; do
    if [[ -f $rc_file ]] && grep -qE "$rc_pattern" "$rc_file"; then
      if [[ -n ${DRY_RUN:-} ]]; then
        log_info "[dry-run] would remove archinit hook from ${rc_file}"
      else
        local tmp
        tmp="$(mktemp)"
        grep -vE "$rc_pattern" "$rc_file" >"$tmp" && mv "$tmp" "$rc_file"
        log_ok "Removed archinit hook from ${rc_file}"
      fi
    fi
  done

  # Remove ARCHINIT_HOME
  if [[ -d $archinit_dir ]]; then
    if [[ -n ${DRY_RUN:-} ]]; then
      log_info "[dry-run] would run: rm -rf '${archinit_dir}'"
    else
      rm -rf "$archinit_dir"
      log_ok "Removed ${archinit_dir}"
    fi
  fi

  # Optionally remove XDG state
  if ((purge)); then
    if [[ -d $state_dir ]]; then
      if [[ -n ${DRY_RUN:-} ]]; then
        log_info "[dry-run] would run: rm -rf '${state_dir}'"
      else
        rm -rf "$state_dir"
        log_ok "Removed ${state_dir}"
      fi
    fi
  fi

  log_ok "archinit uninstalled. Open a new shell to complete cleanup."
}
