#!/usr/bin/env bash
# lib/dotfiles.sh — dman dotfiles manager wrapper
# Sourcing-safe: double-source guard at top.

[[ -n ${_ARCHINIT_DOTFILES:-} ]] && return 0
_ARCHINIT_DOTFILES=1

# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_CORE:-} ]] || source "${ARCHINIT_HOME}/lib/core.sh"
# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_LOG:-} ]] || source "${ARCHINIT_HOME}/lib/log.sh"
# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_CONFIG:-} ]] || source "${ARCHINIT_HOME}/lib/config.sh"

# ---------------------------------------------------------------------------
# dotfiles_init REPO — initialise dman with a repo URL
# Idempotency gate: skips if dman config already present.
# ---------------------------------------------------------------------------
dotfiles_init() {
  local repo="${1:?dotfiles_init: REPO required}"
  if [[ -f "${HOME}/.config/dman/dman.json" ]]; then
    log_info "dman: already initialized (skip); use --force to reinitialize"
    return 0
  fi
  require_cmd dman "dman not found; ensure the 'dev' module has been installed"
  run dman init "$repo"
  log_ok "dman initialized with repo: ${repo}"
}

# ---------------------------------------------------------------------------
# dotfiles_apply — apply dotfiles via dman
# ---------------------------------------------------------------------------
dotfiles_apply() {
  local profile
  profile="$(config_get DOTFILES_PROFILE)"
  profile="${profile:-default}"

  require_cmd dman "dman not found; ensure the 'dev' module has been installed"

  local dry_flag=""
  [[ -n ${DRY_RUN:-} ]] && dry_flag="--dry-run"

  # dman apply is copy-based with pre-apply snapshots — safe to re-run
  # shellcheck disable=SC2086
  run dman apply --profile "$profile" $dry_flag
  log_ok "dman: dotfiles applied (profile: ${profile})"
}

# dotfiles_is_initialized — returns 0 if dman config is present
dotfiles_is_initialized() {
  [[ -f "${HOME}/.config/dman/dman.json" ]]
}
