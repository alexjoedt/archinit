#!/usr/bin/env bash
# cmd/doctor.sh — read-only health/drift report

# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_LOG:-} ]] || source "${ARCHINIT_HOME}/lib/log.sh"
# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_OS:-} ]] || source "${ARCHINIT_HOME}/lib/os.sh"
# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_SNAPSHOT:-} ]] || source "${ARCHINIT_HOME}/lib/snapshot.sh"

cmd_doctor_help() {
  cat <<'EOF'
Usage: archinit doctor

Run a read-only health check across all modules and report their status.
Exits with non-zero if any check fails.
EOF
}

cmd_doctor() {
  local any_failed=0

  _check() {
    local label="$1" result="$2"
    if [[ $result == "ok" ]]; then
      log_ok "  [ok]     ${label}"
    else
      log_error "  [FAIL]   ${label}"
      any_failed=1
    fi
  }

  echo "archinit doctor — $(date)"
  printf '%s\n' "$(printf '%.0s-' {1..60})"

  # OS check
  if [[ -f /etc/os-release ]] && grep -q 'ID=arch' /etc/os-release 2>/dev/null; then
    _check "Arch Linux detected" "ok"
  else
    _check "Arch Linux detected" "fail"
  fi

  # Git repo health
  if git -C "${ARCHINIT_HOME}" rev-parse --git-dir &>/dev/null; then
    _check "git repo at ARCHINIT_HOME" "ok"
  else
    _check "git repo at ARCHINIT_HOME" "fail"
  fi

  # AUR helper
  if has_aur_helper; then
    _check "AUR helper ($(aur_helper))" "ok"
  else
    _check "AUR helper present" "fail"
  fi

  # Module checks
  echo ""
  echo "Modules:"
  local module_dirs
  mapfile -t module_dirs < <(find "${ARCHINIT_HOME}/modules" -maxdepth 2 -name "module.sh" | sort)

  for module_file in "${module_dirs[@]}"; do
    local name
    name="$(bash -c "
      ARCHINIT_HOME='${ARCHINIT_HOME}'
      source '${ARCHINIT_HOME}/lib/core.sh' 2>/dev/null || true
      source '${module_file}' 2>/dev/null || true
      module_name
    " 2>/dev/null || true)"
    [[ -z $name ]] && continue

    if bash -c "
      ARCHINIT_HOME='${ARCHINIT_HOME}'
      source '${ARCHINIT_HOME}/lib/core.sh' 2>/dev/null
      source '${module_file}' 2>/dev/null
      module_check
    " &>/dev/null 2>&1; then
      _check "module: ${name}" "ok"
    else
      _check "module: ${name}" "fail"
    fi
  done

  # Snapshot status
  echo ""
  echo "Snapshots:"
  if snapshot_exists; then
    local latest
    latest="$(snapshot_latest)"
    _check "snapshot exists (latest: ${latest})" "ok"
  else
    _check "snapshot exists" "fail"
    log_warn "  No snapshot found. Run 'archinit snapshot' to create one."
  fi

  printf '%s\n' "$(printf '%.0s-' {1..60})"
  if ((any_failed)); then
    log_error "doctor: some checks FAILED"
    return 1
  else
    log_ok "doctor: all checks passed"
    return 0
  fi
}
