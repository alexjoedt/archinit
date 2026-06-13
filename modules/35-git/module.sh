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
  # Non-interactive path: ASSUME_YES set or stdin is not a TTY
  if [[ -n ${ASSUME_YES:-} ]] || [[ ! -t 0 ]]; then
    _git_install_unattended
    return
  fi

  local choice
  choice="$(ui_menu "Git Setup" \
    "identity" "Setup Git identity (name + email)" \
    "skip" "Skip Git setup")"

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
  # Skip if a git identity is already present in ~/.gitconfig (unless --force)
  if git_is_configured && [[ -z ${FORCE:-} ]]; then
    local cur_name cur_email
    cur_name="$(git config --global user.name 2>/dev/null || true)"
    cur_email="$(git config --global user.email 2>/dev/null || true)"
    log_info "git identity already configured (${cur_name} <${cur_email}>) — skipping (use --force to override)"
    return 0
  fi

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

  [[ -n $name && -n $email ]] || {
    log_warn "Name/email empty; skipping identity setup"
    return 0
  }
  git_set_identity "$name" "$email"
}

_git_setup_auth() {
  # Skip if auth is already configured (~/.git-credentials, credential.helper, or SSH key)
  if git_auth_configured && [[ -z ${FORCE:-} ]]; then
    log_info "git auth already configured — skipping (use --force to override)"
    return 0
  fi

  local method
  method="$(ui_menu "Git Auth Method" \
    "ssh" "Use SSH key (recommended)" \
    "token" "Use HTTPS personal access token" \
    "skip" "Skip auth setup")"

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

# ---------------------------------------------------------------------------
# Unattended path — no prompts; driven entirely by config keys
# ---------------------------------------------------------------------------
_git_install_unattended() {
  local name email
  name="$(config_get GIT_USER_NAME)"
  email="$(config_get GIT_USER_EMAIL)"

  if [[ -z $name || -z $email ]]; then
    log_warn "git: GIT_USER_NAME or GIT_USER_EMAIL not configured — skipping"
    log_warn "     set them with: archinit config GIT_USER_NAME \"Your Name\""
    return 0
  fi

  git_set_identity "$name" "$email"

  # Skip auth if already configured (~/.git-credentials, credential.helper, or SSH key)
  if git_auth_configured && [[ -z ${FORCE:-} ]]; then
    log_info "git: auth already configured — skipping"
    return 0
  fi

  local method
  method="$(config_get GIT_AUTH_METHOD)"
  method="${method:-ssh}"

  case "$method" in
    ssh)
      git_setup_ssh_key "$email"
      log_warn "git: SSH key generated — add the public key to GitHub manually"
      log_warn "     then test with: ssh -T git@github.com"
      ;;
    token)
      local secrets_file="${ARCHINIT_STATE}/secrets.local"
      if [[ -f $secrets_file ]] && grep -q '^GITHUB_TOKEN=' "$secrets_file"; then
        run git config --global credential.helper store
        log_ok "git: HTTPS credential.helper configured (token found in secrets.local)"
      else
        log_warn "git: token auth selected but no secrets.local found — skipping"
        log_warn "     run 'archinit tui' or 'archinit install git --force' to set up interactively"
      fi
      ;;
    skip | *)
      log_info "git: auth method '${method}' — skipping auth setup"
      ;;
  esac

  # gh auth login requires a browser/TTY — skip unattended
  local setup_gh
  setup_gh="$(config_get SETUP_GH_CLI)"
  if [[ ${setup_gh:-true} == "true" ]]; then
    if has_cmd gh && gh auth status &>/dev/null; then
      log_ok "git: gh CLI already authenticated"
    else
      log_warn "git: gh CLI auth requires an interactive terminal — run 'gh auth login' manually"
    fi
  fi
}
