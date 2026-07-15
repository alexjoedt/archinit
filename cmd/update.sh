#!/usr/bin/env bash
# cmd/update.sh — self-update archinit and optionally upgrade packages

# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_LOG:-} ]] || source "${ARCHINIT_HOME}/lib/log.sh"
# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_UPDATE:-} ]] || source "${ARCHINIT_HOME}/lib/update.sh"
# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_SNAPSHOT:-} ]] || source "${ARCHINIT_HOME}/lib/snapshot.sh"
# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_INSTALL:-} ]] || source "${ARCHINIT_HOME}/lib/install.sh"
# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_OS:-} ]] || source "${ARCHINIT_HOME}/lib/os.sh"
# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_PKG:-} ]] || source "${ARCHINIT_HOME}/lib/pkg.sh"

cmd_update_help() {
  cat <<'EOF'
Usage: archinit update [--no-sysupgrade] [--no-modules] [--no-snapshot]

Self-update archinit from git, optionally upgrade system packages, re-run
pending modules, and merge snapshot packages.

Options:
  --no-sysupgrade   Skip pacman/yay system upgrade
  --no-modules      Skip re-running pending modules
  --no-snapshot     Skip merging snapshot packages
  --dry-run         Print commands without executing
EOF
}

cmd_update() {
  local no_sysupgrade=0 no_modules=0 no_snapshot=0

  for arg in "$@"; do
    case "$arg" in
      --no-sysupgrade) no_sysupgrade=1 ;;
      --no-modules) no_modules=1 ;;
      --no-snapshot) no_snapshot=1 ;;
      --help | -h)
        cmd_update_help
        exit 0
        ;;
      --*) ;;
    esac
  done

  log_init

  # 1. Self-update archinit
  update_self

  # 2. System package upgrade
  if ((no_sysupgrade == 0)); then
    if has_aur_helper; then
      run "$(aur_helper)" -Syu --noconfirm
    elif has_cmd pacman; then
      as_root pacman -Syu --noconfirm
    fi
  fi

  # 3. Re-run pending modules
  if ((no_modules == 0)); then
    run_modules all
  fi

  # 4. Merge snapshot packages
  local install_snapshot
  install_snapshot="$(config_get INSTALL_SNAPSHOT_PACKAGES)"
  install_snapshot="${install_snapshot:-true}"

  if ((no_snapshot == 0)) && [[ $install_snapshot == "true" ]]; then
    if snapshot_exists; then
      log_info "Merging latest snapshot packages..."
      local native_pkgs foreign_pkgs
      native_pkgs="$(snapshot_native_packages)"
      foreign_pkgs="$(snapshot_foreign_packages)"

      if [[ -n $native_pkgs ]]; then
        # shellcheck disable=SC2086
        pkg_install_official $native_pkgs
      fi
      if [[ -n $foreign_pkgs ]]; then
        # shellcheck disable=SC2086
        pkg_install_aur $foreign_pkgs
      fi
    fi
  fi

  log_ok "archinit update complete"
}
