#!/usr/bin/env bash
# lib/update.sh — self-update logic for archinit
# Sourcing-safe: double-source guard at top.

[[ -n ${_ARCHINIT_UPDATE:-} ]] && return 0
_ARCHINIT_UPDATE=1

# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_CORE:-} ]] || source "${ARCHINIT_HOME}/lib/core.sh"
# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_LOG:-} ]] || source "${ARCHINIT_HOME}/lib/log.sh"

# update_self — git fast-forward pull; warn on local changes; touch .last_update
update_self() {
  local repo_dir="${ARCHINIT_HOME}"

  if [[ -n ${DRY_RUN:-} ]]; then
    log_info "[dry-run] would run: git -C '${repo_dir}' fetch && git -C '${repo_dir}' merge --ff-only"
    return 0
  fi

  # Check for local modifications — warn and abort update rather than clobber
  if ! git -C "$repo_dir" diff --quiet 2>/dev/null || \
     ! git -C "$repo_dir" diff --cached --quiet 2>/dev/null; then
    log_warn "archinit: local changes detected in ${repo_dir}; skipping self-update to avoid clobbering"
    log_warn "  Commit or stash your changes, then run 'archinit update' again."
    return 0
  fi

  log_info "Fetching archinit updates..."
  git -C "$repo_dir" fetch --quiet

  local behind
  behind="$(git -C "$repo_dir" rev-list HEAD..@\{u\} --count 2>/dev/null || echo "0")"
  if [[ $behind -eq 0 ]]; then
    log_info "archinit is already up to date"
  else
    log_info "Fast-forwarding ${behind} commit(s)..."
    git -C "$repo_dir" merge --ff-only
    log_ok "archinit updated successfully"
  fi

  # Touch the throttle file
  touch "${ARCHINIT_STATE}/.last_update" 2>/dev/null || true
}
