#!/usr/bin/env bash
# modules/30-desktop/module.sh — Hyprland Wayland desktop + sddm display manager

# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_CORE:-} ]] || source "${ARCHINIT_HOME}/lib/core.sh"
# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_PKG:-} ]] || source "${ARCHINIT_HOME}/lib/pkg.sh"
# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_OS:-} ]] || source "${ARCHINIT_HOME}/lib/os.sh"
# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_SERVICE:-} ]] || source "${ARCHINIT_HOME}/lib/service.sh"
# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_CONFIG:-} ]] || source "${ARCHINIT_HOME}/lib/config.sh"

module_name() { echo "desktop"; }
module_class() { echo "desktop"; }
module_describe() { echo "Hyprland Wayland stack + sddm display manager"; }
module_requires() { echo "base services"; }

module_check() {
  local pkg_list="${ARCHINIT_HOME}/config/packages/desktop.txt"
  while IFS= read -r pkg; do
    pkg_is_installed "$pkg" || return 1
  done < <(pkg_read_list "$pkg_list")

  local dm
  dm="$(config_get DISPLAY_MANAGER)"
  dm="${dm:-sddm}"
  systemctl is-enabled --quiet "$dm" 2>/dev/null || return 1
  return 0
}

module_install() {
  assert_arch
  pkg_install_list desktop

  local dm
  dm="$(config_get DISPLAY_MANAGER)"
  dm="${dm:-sddm}"
  service_enable "$dm"
}
