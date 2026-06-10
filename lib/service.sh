#!/usr/bin/env bash
# lib/service.sh — idempotent systemd service management (system + user)
# Requires: lib/core.sh, lib/log.sh sourced first.

[[ -n ${_ARCHINIT_SERVICE:-} ]] && return 0
_ARCHINIT_SERVICE=1

# service_enable UNIT — enable and start a system unit idempotently
service_enable() {
  local unit="$1"
  if systemctl is-enabled --quiet "$unit" 2>/dev/null; then
    log_debug "service: $unit already enabled, skipping"
    return 0
  fi
  log_info "service: enabling $unit"
  run as_root systemctl enable --now "$unit"
}

# service_enable_user UNIT — enable and start a user unit idempotently
service_enable_user() {
  local unit="$1"
  if systemctl --user is-enabled --quiet "$unit" 2>/dev/null; then
    log_debug "service(user): $unit already enabled, skipping"
    return 0
  fi
  log_info "service(user): enabling $unit"
  run systemctl --user enable --now "$unit"
}

# service_is_enabled UNIT — return 0 if a system unit is enabled
service_is_enabled() {
  systemctl is-enabled --quiet "$1" 2>/dev/null
}

# service_is_enabled_user UNIT — return 0 if a user unit is enabled
service_is_enabled_user() {
  systemctl --user is-enabled --quiet "$1" 2>/dev/null
}
