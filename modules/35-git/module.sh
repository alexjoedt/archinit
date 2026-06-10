#!/usr/bin/env bash
# modules/35-git/module.sh — interactive git identity + auth + optional gh CLI setup

# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_CORE:-} ]] || source "${ARCHINIT_HOME}/lib/core.sh"
# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_GIT:-} ]] || source "${ARCHINIT_HOME}/lib/git.sh"
# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_UI:-} ]] || source "${ARCHINIT_HOME}/lib/ui.sh"
# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_CONFIG:-} ]] || source "${ARCHINIT_HOME}/lib/config.sh"
# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_PKG:-} ]] || source "${ARCHINIT_HOME}/lib/pkg.sh"

module_name() { echo "git"; }
module_class() { echo "base"; }
module_describe() { echo "Git global identity and GitHub authentication (SSH/token/gh CLI)"; }
module_requires() { echo "base"; }

module_check() {
  # Consider satisfied if git identity is configured
  git_is_configured
}

module_install() {
  local choice
  choice="$(ui_menu "Git Setup" \
    "identity" "Setup Git identity (name + email)" \
    "skip"     "Skip Git setup")"

  case "$choice" in
    skip)
      log_info "Skipping git setup"
      return 0
      ;;
    identity | *)
      _git_setup_identity
      _git_setup_auth
      _git_maybe_gh
      ;;
  esac
}

_git_setup_identity() {
  local name email

  # Pre-populate from config
  name="$(config_get GIT_USER_NAME)"
  email="$(config_get GIT_USER_EMAIL)"

  if [[ -z $name ]]; then
    printf "Git user name: " >&2
    read -r name
  fi
  if [[ -z $email ]]; then
    printf "Git user email: " >&2
    read -r email
  fi

  [[ -n $name && -n $email ]] || { log_warn "Name/email empty; skipping identity setup"; return 0; }
  git_set_identity "$name" "$email"
}

_git_setup_auth() {
  local method
  method="$(ui_menu "Git Auth Method" \
    "ssh"   "Use SSH key (recommended)" \
    "token" "Use HTTPS personal access token" \
    "skip"  "Skip auth setup")"

  case "$method" in
    ssh)
      local email
      email="$(git config --global user.email 2>/dev/null || true)"
      git_setup_ssh_key "$email"
      if ui_confirm "Test SSH connection to GitHub now?"; then
        git_test_ssh || true
      fi
      ;;
    token)
      git_setup_https_token
      ;;
    skip | *)
      log_info "Skipping auth setup"
      ;;
  esac
}

_git_maybe_gh() {
  local setup_gh
  setup_gh="$(config_get SETUP_GH_CLI)"
  setup_gh="${setup_gh:-true}"

  if [[ $setup_gh != "true" ]]; then
    return 0
  fi

  if ui_confirm "Set up gh CLI (GitHub CLI)?"; then
    gh_setup
  else
    log_info "Skipping gh CLI setup"
  fi
}
