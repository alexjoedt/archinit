#!/usr/bin/env bash
# modules/50-go/module.sh — install Go via the official upstream installer

# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_CORE:-} ]] || source "${ARCHINIT_HOME}/lib/core.sh"
# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_LOG:-} ]] || source "${ARCHINIT_HOME}/lib/log.sh"

module_name()     { echo "go"; }
module_class()    { echo "dev"; }
module_describe() { echo "Go toolchain via official upstream installer (latest stable)"; }
module_requires() { echo "base"; }

_GO_INSTALLER_URL="https://gist.githubusercontent.com/alexjoedt/9c61f9cc4ce211430257b2febd68be9f/raw/6de1a4962fdfaa5d6f7dc69bb6cd074c102598ff/install_go.sh"
_GO_BIN="/usr/local/go/bin/go"

module_check() {
  [[ -x ${_GO_BIN} ]]
}

module_install() {
  assert_arch
  require_cmd curl "curl is required to download the Go installer"

  if [[ -n ${DRY_RUN:-} ]]; then
    log_info "[dry-run] would download and run Go upstream installer"
    return 0
  fi

  local installer
  installer="$(mktemp /tmp/install_go.XXXXXX.sh)"
  trap 'rm -f "$installer"' RETURN

  log_info "go: downloading upstream installer"
  curl --fail --silent --show-error \
    --max-time 120 --connect-timeout 15 \
    --location "${_GO_INSTALLER_URL}" \
    --output "$installer"

  chmod +x "$installer"
  log_info "go: running upstream installer"
  bash "$installer" --system-install

  [[ -x ${_GO_BIN} ]] || die "go: installation failed — ${_GO_BIN} not found"
  log_ok "go: $("${_GO_BIN}" version)"
}
