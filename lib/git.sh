#!/usr/bin/env bash
# lib/git.sh — git identity and auth setup helpers
# Sourcing-safe: double-source guard at top.

[[ -n ${_ARCHINIT_GIT:-} ]] && return 0
_ARCHINIT_GIT=1

# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_CORE:-} ]] || source "${ARCHINIT_HOME}/lib/core.sh"
# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_LOG:-} ]] || source "${ARCHINIT_HOME}/lib/log.sh"

# ---------------------------------------------------------------------------
# Identity
# ---------------------------------------------------------------------------

# git_is_configured — returns 0 if both user.name and user.email are set globally
git_is_configured() {
  local name email
  name="$(git config --global user.name 2>/dev/null || true)"
  email="$(git config --global user.email 2>/dev/null || true)"
  [[ -n $name && -n $email ]]
}

# git_set_identity NAME EMAIL — set global git identity (idempotent: only sets if empty or --force)
git_set_identity() {
  local name="${1:?git_set_identity: NAME required}"
  local email="${2:?git_set_identity: EMAIL required}"

  local cur_name cur_email
  cur_name="$(git config --global user.name 2>/dev/null || true)"
  cur_email="$(git config --global user.email 2>/dev/null || true)"

  if [[ -z $cur_name || -n ${FORCE:-} ]]; then
    run git config --global user.name "$name"
    log_ok "git user.name set to: ${name}"
  else
    log_info "git user.name already set to: ${cur_name} (use --force to override)"
  fi

  if [[ -z $cur_email || -n ${FORCE:-} ]]; then
    run git config --global user.email "$email"
    log_ok "git user.email set to: ${email}"
  else
    log_info "git user.email already set to: ${cur_email} (use --force to override)"
  fi
}

# ---------------------------------------------------------------------------
# HTTPS token auth
# ---------------------------------------------------------------------------

# git_setup_https_token — configure credential.helper and optionally store token
# Secrets read via read -rs; NEVER echoed, logged, or passed on the command line.
git_setup_https_token() {
  if [[ -n ${DRY_RUN:-} ]]; then
    log_info "[dry-run] would configure git credential.helper and prompt for token"
    return 0
  fi

  local secrets_file="${ARCHINIT_STATE}/secrets.local"

  run git config --global credential.helper store

  local github_user token
  printf "GitHub username: " >&2
  read -r github_user
  printf "GitHub PAT (input hidden): " >&2
  read -rs token
  printf '\n' >&2

  if [[ -z $github_user || -z $token ]]; then
    log_warn "No credentials provided; skipping token storage"
    return 0
  fi

  # Write to ~/.git-credentials (used by credential.helper store)
  local creds_file="${HOME}/.git-credentials"
  # Remove any existing entry for github.com to avoid duplicates
  if [[ -f $creds_file ]]; then
    local tmp
    tmp="$(mktemp)"
    grep -v 'github.com' "$creds_file" >"$tmp" || true
    mv "$tmp" "$creds_file"
  fi
  printf 'https://%s:%s@github.com\n' "$github_user" "$token" >>"$creds_file"
  chmod 600 "$creds_file"
  log_ok "GitHub credentials stored in ${creds_file}"

  # Also store token in secrets.local for dman authenticated URL construction
  ensure_dir "$(dirname "$secrets_file")"
  # Remove existing entry
  if [[ -f $secrets_file ]]; then
    local tmp
    tmp="$(mktemp)"
    grep -v '^GITHUB_TOKEN=' "$secrets_file" >"$tmp" || true
    mv "$tmp" "$secrets_file"
    grep -v '^GITHUB_USER=' "$secrets_file" >"$tmp" || true
    mv "$tmp" "$secrets_file"
  fi
  printf 'GITHUB_USER=%s\n' "$github_user" >>"$secrets_file"
  printf 'GITHUB_TOKEN=%s\n' "$token" >>"$secrets_file"
  chmod 600 "$secrets_file"
  log_ok "Token also stored in ${secrets_file} (chmod 600) for dotfiles auth"

  # Unset in-memory — do not keep token in env
  unset token
}

# ---------------------------------------------------------------------------
# SSH key auth
# ---------------------------------------------------------------------------

# git_setup_ssh_key [EMAIL] — generate ed25519 key if absent, start agent, print pubkey
git_setup_ssh_key() {
  local email="${1:-$(git config --global user.email 2>/dev/null || true)}"
  local key_file="${HOME}/.ssh/id_ed25519"

  if [[ -f ${key_file} ]]; then
    log_info "SSH key already exists at ${key_file}; skipping generation"
  else
    if [[ -n ${DRY_RUN:-} ]]; then
      log_info "[dry-run] would run: ssh-keygen -t ed25519 -C \"${email}\" -f \"${key_file}\""
    else
      run ssh-keygen -t ed25519 -C "${email}" -f "${key_file}"
      log_ok "SSH key generated: ${key_file}"
    fi
  fi

  if [[ -z ${DRY_RUN:-} ]]; then
    # Start agent and add key
    if ! ssh-add -l &>/dev/null; then
      eval "$(ssh-agent -s)" >/dev/null
    fi
    ssh-add "$key_file" 2>/dev/null || true
  fi

  # Print public key for the user to add to GitHub
  if [[ -f ${key_file}.pub ]]; then
    log_info "Your public key (add to GitHub > Settings > SSH keys):"
    cat "${key_file}.pub"
    printf '\n'
  fi
}

# git_test_ssh — test SSH connectivity to GitHub
git_test_ssh() {
  log_info "Testing SSH connection to GitHub..."
  if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
    log_ok "SSH authentication to GitHub successful"
    return 0
  else
    log_warn "SSH test did not confirm authentication (may still work)"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# gh CLI
# ---------------------------------------------------------------------------

# gh_setup — install github-cli and run gh auth login
gh_setup() {
  if ! has_cmd gh; then
    log_info "Installing github-cli..."
    pkg_install_official github-cli
  fi

  if gh auth status &>/dev/null; then
    log_info "gh: already authenticated"
    return 0
  fi

  if [[ -n ${DRY_RUN:-} ]]; then
    log_info "[dry-run] would run: gh auth login"
    return 0
  fi

  run gh auth login
}
