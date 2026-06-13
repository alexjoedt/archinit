#!/usr/bin/env bash
# modules/40-dev/module.sh — AUR dev tools and applications

# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_CORE:-} ]] || source "${ARCHINIT_HOME}/lib/core.sh"
# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_PKG:-} ]] || source "${ARCHINIT_HOME}/lib/pkg.sh"
# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_OS:-} ]] || source "${ARCHINIT_HOME}/lib/os.sh"

module_name() { echo "dev"; }
module_class() { echo "aur"; }
module_describe() { echo "AUR dev tools and applications"; }
module_requires() { echo "aur-helper"; }

module_check() {
  # Satisfied only when every package in the AUR list is installed
  pkg_list_satisfied aur
}

module_install() {
  assert_arch

  # Install all AUR packages
  pkg_install_list aur
}

