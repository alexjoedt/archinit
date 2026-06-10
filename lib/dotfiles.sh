#!/usr/bin/env bash
# lib/dotfiles.sh — swappable dotfiles manager abstraction (default: dman)
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
# dotfiles_init REPO — initialise the dotfiles manager with a repo URL
# Idempotency gate: skips if manager config already present.
# ---------------------------------------------------------------------------
dotfiles_init() {
  local repo="${1:?dotfiles_init: REPO required}"
  local manager
  manager="$(config_get DOTFILES_MANAGER)"
  manager="${manager:-dman}"

  case "$manager" in
    dman)
      _dman_init "$repo"
      ;;
    chezmoi)
      _chezmoi_init "$repo"
      ;;
    stow)
      _stow_init "$repo"
      ;;
    *)
      die "dotfiles: unknown DOTFILES_MANAGER: ${manager}"
      ;;
  esac
}

# ---------------------------------------------------------------------------
# dotfiles_apply — apply dotfiles from the configured manager
# ---------------------------------------------------------------------------
dotfiles_apply() {
  local manager profile dry_flag
  manager="$(config_get DOTFILES_MANAGER)"
  manager="${manager:-dman}"
  profile="$(config_get DOTFILES_PROFILE)"
  profile="${profile:-default}"

  case "$manager" in
    dman)
      _dman_apply "$profile"
      ;;
    chezmoi)
      _chezmoi_apply
      ;;
    stow)
      _stow_apply
      ;;
    *)
      die "dotfiles: unknown DOTFILES_MANAGER: ${manager}"
      ;;
  esac
}

# dotfiles_is_initialized — returns 0 if the manager appears configured
dotfiles_is_initialized() {
  local manager
  manager="$(config_get DOTFILES_MANAGER)"
  manager="${manager:-dman}"

  case "$manager" in
    dman)
      [[ -f "${HOME}/.config/dman/dman.json" ]]
      ;;
    chezmoi)
      [[ -d "${HOME}/.local/share/chezmoi" ]]
      ;;
    stow)
      # stow: just check if the dotfiles directory exists
      [[ -d "${HOME}/.dotfiles" ]]
      ;;
    *)
      return 1
      ;;
  esac
}

# ---------------------------------------------------------------------------
# dman backend
# ---------------------------------------------------------------------------

_dman_init() {
  local repo="$1"
  if [[ -f "${HOME}/.config/dman/dman.json" ]]; then
    log_info "dman: already initialized (skip); use --force to reinitialize"
    return 0
  fi

  require_cmd dman "dman not found; ensure the 'dev' module has been installed"
  run dman init "$repo"
  log_ok "dman initialized with repo: ${repo}"
}

_dman_apply() {
  local profile="$1"
  require_cmd dman "dman not found; ensure the 'dev' module has been installed"

  local dry_flag=""
  [[ -n ${DRY_RUN:-} ]] && dry_flag="--dry-run"

  # dman apply is copy-based with pre-apply snapshots — safe to re-run
  # shellcheck disable=SC2086
  run dman apply --profile "$profile" $dry_flag
  log_ok "dman: dotfiles applied (profile: ${profile})"
}

# ---------------------------------------------------------------------------
# chezmoi backend (stub)
# ---------------------------------------------------------------------------

_chezmoi_init() {
  local repo="$1"
  require_cmd chezmoi "chezmoi not found"
  [[ -d "${HOME}/.local/share/chezmoi" ]] && {
    log_info "chezmoi: already initialized"
    return 0
  }
  run chezmoi init "$repo"
}

_chezmoi_apply() {
  require_cmd chezmoi "chezmoi not found"
  local dry_flag=""
  [[ -n ${DRY_RUN:-} ]] && dry_flag="--dry-run"
  # shellcheck disable=SC2086
  run chezmoi apply $dry_flag
}

# ---------------------------------------------------------------------------
# stow backend (stub)
# ---------------------------------------------------------------------------

_stow_init() {
  local repo="$1"
  require_cmd git "git not found"
  [[ -d "${HOME}/.dotfiles" ]] && {
    log_info "stow: dotfiles dir already present"
    return 0
  }
  run git clone "$repo" "${HOME}/.dotfiles"
}

_stow_apply() {
  require_cmd stow "stow not found"
  [[ -n ${DRY_RUN:-} ]] && {
    log_info "[dry-run] would run: stow -d ~/.dotfiles -t ~ ."
    return 0
  }
  (cd "${HOME}/.dotfiles" && run stow -t "${HOME}" .)
}
