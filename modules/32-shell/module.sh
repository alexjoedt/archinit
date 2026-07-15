#!/usr/bin/env bash
# modules/32-shell/module.sh — desktop shell layer (custom Quickshell or Noctalia v5)

# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_CORE:-} ]] || source "${ARCHINIT_HOME}/lib/core.sh"
# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_PKG:-} ]] || source "${ARCHINIT_HOME}/lib/pkg.sh"
# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_OS:-} ]] || source "${ARCHINIT_HOME}/lib/os.sh"
# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_CONFIG:-} ]] || source "${ARCHINIT_HOME}/lib/config.sh"

module_name() { echo "shell"; }
module_class() { echo "desktop"; }
module_describe() { echo "Desktop shell layer (custom Quickshell or Noctalia v5)"; }
module_requires() { echo "aur-helper"; }

# ---------------------------------------------------------------------------
# _shell_selected — resolve the configured shell, defaulting to 'custom'
# ---------------------------------------------------------------------------
_shell_selected() {
  local shell
  shell="$(config_get DESKTOP_SHELL)"
  echo "${shell:-custom}"
}

# ---------------------------------------------------------------------------
# _shell_assert_valid NAME — abort on an unknown shell flavour
# ---------------------------------------------------------------------------
_shell_assert_valid() {
  case "$1" in
    custom | noctalia) return 0 ;;
    *) die "Unknown DESKTOP_SHELL '$1' (expected: custom | noctalia)" ;;
  esac
}

# ---------------------------------------------------------------------------
# _shell_classes NAME — print the package list classes for a shell, one per
# line, skipping any whose list file does not exist.
# ---------------------------------------------------------------------------
_shell_classes() {
  local name="$1" class
  for class in "shell-${name}" "shell-${name}-aur"; do
    [[ -f "${ARCHINIT_HOME}/config/packages/${class}.txt" ]] && echo "$class"
  done
}

module_check() {
  local shell
  shell="$(_shell_selected)"
  _shell_assert_valid "$shell"

  local class
  while IFS= read -r class; do
    pkg_list_satisfied "$class" || return 1
  done < <(_shell_classes "$shell")
  return 0
}

module_install() {
  assert_arch

  local shell
  shell="$(_shell_selected)"
  _shell_assert_valid "$shell"

  log_info "shell: installing '${shell}' desktop shell layer"

  local class installed=0
  while IFS= read -r class; do
    pkg_install_list "$class"
    installed=1
  done < <(_shell_classes "$shell")

  if [[ $installed -eq 0 ]]; then
    log_warn "shell: no package list found for '${shell}'"
  fi
}
