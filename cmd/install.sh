#!/usr/bin/env bash
# cmd/install.sh — install modules idempotently

# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_LOG:-} ]] || source "${ARCHINIT_HOME}/lib/log.sh"
# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_INSTALL:-} ]] || source "${ARCHINIT_HOME}/lib/install.sh"
# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_SNAPSHOT:-} ]] || source "${ARCHINIT_HOME}/lib/snapshot.sh"

cmd_install_help() {
  cat <<'EOF'
Usage: archinit install [module...] [--no-snapshot]

Install one or more modules. If no modules are specified, installs all modules
configured in DEFAULT_MODULES (or all available modules).

Options:
  --no-snapshot   Do not install snapshot packages after modules
  --force         Re-run module_install even if module_check passes
  --dry-run       Print commands without executing

Examples:
  archinit install
  archinit install base aur-helper
  archinit install dev --force
EOF
}

cmd_install() {
  local -a modules=()
  local no_snapshot=0

  for arg in "$@"; do
    case "$arg" in
      --no-snapshot) no_snapshot=1 ;;
      --help | -h)
        cmd_install_help
        exit 0
        ;;
      --*) ;; # global flags already parsed
      *) modules+=("$arg") ;;
    esac
  done

  # Default: use DEFAULT_MODULES or "all"
  if [[ ${#modules[@]} -eq 0 ]]; then
    local default_modules
    default_modules="$(config_get DEFAULT_MODULES)"
    if [[ -n $default_modules ]]; then
      IFS=' ' read -ra modules <<<"$default_modules"
    else
      modules=("all")
    fi
  fi

  log_init

  run_modules "${modules[@]}"

  # Optionally install snapshot packages
  local install_snapshot
  install_snapshot="$(config_get INSTALL_SNAPSHOT_PACKAGES)"
  install_snapshot="${install_snapshot:-true}"

  if [[ $no_snapshot -eq 0 && $install_snapshot == "true" ]]; then
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
    else
      log_debug "No snapshot found; skipping snapshot package merge"
    fi
  fi
}
