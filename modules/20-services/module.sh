#!/usr/bin/env bash
# modules/20-services/module.sh — enable common systemd services

# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_CORE:-} ]] || source "${ARCHINIT_HOME}/lib/core.sh"
# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_SERVICE:-} ]] || source "${ARCHINIT_HOME}/lib/service.sh"

module_name() { echo "services"; }
module_class() { echo "service"; }
module_describe() { echo "Enable common system services (NetworkManager, sshd, pipewire)"; }
module_requires() { echo "base"; }

# Services to enable at system level
_SYSTEM_SERVICES=(NetworkManager)
# Services to enable at user level
_USER_SERVICES=(pipewire wireplumber pipewire-pulse)

module_check() {
  for unit in "${_SYSTEM_SERVICES[@]}"; do
    systemctl is-enabled --quiet "$unit" 2>/dev/null || return 1
  done
  for unit in "${_USER_SERVICES[@]}"; do
    systemctl --user is-enabled --quiet "$unit" 2>/dev/null || return 1
  done
  return 0
}

module_install() {
  for unit in "${_SYSTEM_SERVICES[@]}"; do
    service_enable "$unit"
  done
  for unit in "${_USER_SERVICES[@]}"; do
    service_enable_user "$unit"
  done
}
