#!/usr/bin/env bash
# modules/10-aur-helper/module.sh — bootstrap yay from source

# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_CORE:-} ]] || source "${ARCHINIT_HOME}/lib/core.sh"
# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_OS:-} ]] || source "${ARCHINIT_HOME}/lib/os.sh"
# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_PKG:-} ]] || source "${ARCHINIT_HOME}/lib/pkg.sh"

module_name() { echo "aur-helper"; }
module_class() { echo "base"; }
module_describe() { echo "Bootstrap yay AUR helper from source"; }
module_requires() { echo ""; }

module_check() {
  has_aur_helper
}

module_install() {
  assert_arch
  is_root && die "Do not run the aur-helper module as root; makepkg must run as a normal user."

  # Ensure build dependencies
  pkg_install_official base-devel git

  local tmpdir
  tmpdir="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '${tmpdir}'" EXIT

  log_info "Cloning yay from AUR..."
  run git clone --depth=1 https://aur.archlinux.org/yay.git "$tmpdir/yay"

  log_info "Building and installing yay..."
  (cd "$tmpdir/yay" && run makepkg -si --noconfirm)

  log_ok "yay installed successfully"
}
