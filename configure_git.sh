#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

log_info() { printf '[INFO] %s\n' "$*"; }
log_ok() { printf '[ OK ] %s\n' "$*"; }
log_warn() { printf '[WARN] %s\n' "$*"; }
log_error() { printf '[ERR ] %s\n' "$*"; }
die() {
  log_error "$*"
  exit 1
}

require_cmd() {
  local cmd="${1:?command required}"
  command -v "$cmd" >/dev/null 2>&1 || die "required command not found: ${cmd}"
}

configure_git_identity() {
  local cur_name cur_email name email

  cur_name="$(git config --global user.name 2>/dev/null || true)"
  cur_email="$(git config --global user.email 2>/dev/null || true)"

  if [[ -n "$cur_name" && -n "$cur_email" ]]; then
    log_info "Git identity already configured: ${cur_name} <${cur_email}>"
    return 0
  fi

  if [[ -n "$cur_name" ]]; then
    name="$cur_name"
    log_info "Using existing git user.name: ${name}"
  else
    printf 'Git user name: '
    read -r name
  fi

  if [[ -n "$cur_email" ]]; then
    email="$cur_email"
    log_info "Using existing git user.email: ${email}"
  else
    printf 'Git user email: '
    read -r email
  fi

  [[ -n "$name" && -n "$email" ]] || {
    log_warn "Name/email empty, skipping git identity setup"
    return 0
  }

  if [[ -z "$cur_name" ]]; then
    git config --global user.name "$name"
    log_ok "Set git user.name to ${name}"
  fi

  if [[ -z "$cur_email" ]]; then
    git config --global user.email "$email"
    log_ok "Set git user.email to ${email}"
  fi
}

configure_git_https_token() {
  local github_user token creds_file tmp_file

  git config --global credential.helper store
  log_ok "Configured git credential.helper=store"

  printf 'GitHub username: '
  read -r github_user
  printf 'GitHub PAT (input hidden): ' >&2
  read -rs token
  printf '\n' >&2

  if [[ -z "$github_user" || -z "$token" ]]; then
    log_warn "Credentials empty, skipping token storage"
    return 0
  fi

  creds_file="${HOME}/.git-credentials"

  if [[ -f "$creds_file" ]]; then
    tmp_file="$(mktemp)"
    grep -v 'github.com' "$creds_file" >"$tmp_file" || true
    mv "$tmp_file" "$creds_file"
  fi

  printf 'https://%s:%s@github.com\n' "$github_user" "$token" >>"$creds_file"
  chmod 600 "$creds_file"
  unset token

  log_ok "Stored GitHub credentials in ${creds_file}"
}

main() {
  require_cmd git
  require_cmd grep
  require_cmd mktemp

  configure_git_identity
  configure_git_https_token

  log_ok "All done"
}

main "$@"
