#!/usr/bin/env bash
# modules/40-dev/module.sh — AUR dev tools + dotfile application via dman

# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_CORE:-} ]] || source "${ARCHINIT_HOME}/lib/core.sh"
# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_PKG:-} ]] || source "${ARCHINIT_HOME}/lib/pkg.sh"
# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_OS:-} ]] || source "${ARCHINIT_HOME}/lib/os.sh"
# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_CONFIG:-} ]] || source "${ARCHINIT_HOME}/lib/config.sh"
# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_DOTFILES:-} ]] || source "${ARCHINIT_HOME}/lib/dotfiles.sh"

module_name() { echo "dev"; }
module_class() { echo "aur"; }
module_describe() { echo "AUR dev tools and dotfile application via dman"; }
module_requires() { echo "aur-helper git"; }

module_check() {
  # Check dman is present and config is initialized
  has_cmd dman && dotfiles_is_initialized
}

module_install() {
  assert_arch

  # Install all AUR packages (includes dman)
  pkg_install_list aur

  # Apply dotfiles via the configured manager
  local dotfiles_repo
  dotfiles_repo="$(config_get DOTFILES_REPO)"

  if [[ -z $dotfiles_repo ]]; then
    log_warn "DOTFILES_REPO not set; skipping dotfile application"
    log_warn "Set it with: archinit config DOTFILES_REPO <url>"
    return 0
  fi

  # Determine the best auth for the dotfiles repo URL
  # Prefer SSH or gh auth; fall back to stored token from secrets.local
  local secrets_file="${ARCHINIT_STATE}/secrets.local"
  if [[ $dotfiles_repo == https://* && -f $secrets_file ]]; then
    # shellcheck source=/dev/null
    source "$secrets_file"
    if [[ -n ${GITHUB_USER:-} && -n ${GITHUB_TOKEN:-} ]]; then
      # Build authenticated HTTPS URL (token never logged)
      local base_url="${dotfiles_repo#https://}"
      dotfiles_repo="https://${GITHUB_USER}:${GITHUB_TOKEN}@${base_url}"
      # Unset after use
      unset GITHUB_TOKEN
    fi
  fi

  dotfiles_init "$dotfiles_repo"
  dotfiles_apply
}
