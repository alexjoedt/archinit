#!/usr/bin/env bash
# modules/00-base/module.sh — install official base packages

# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_CORE:-} ]] || source "${ARCHINIT_HOME}/lib/core.sh"
# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_PKG:-} ]] || source "${ARCHINIT_HOME}/lib/pkg.sh"
# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_OS:-} ]] || source "${ARCHINIT_HOME}/lib/os.sh"

module_name() { echo "base"; }
module_class() { echo "base"; }
module_describe() { echo "Core CLI and system packages (official repos)"; }
module_requires() { echo ""; }

module_check() {
  local pkg_list="${ARCHINIT_HOME}/config/packages/base.txt"
  while IFS= read -r pkg; do
    pkg_is_installed "$pkg" || return 1
  done < <(pkg_read_list "$pkg_list")
  return 0
}

module_install() {
  assert_arch
  pkg_install_list base
}
