#!/usr/bin/env bash
# lib/log.sh — leveled logging with color and per-run file logging
# Requires: lib/core.sh sourced first (ARCHINIT_STATE, NO_COLOR, VERBOSE, QUIET).

[[ -n ${_ARCHINIT_LOG:-} ]] && return 0
_ARCHINIT_LOG=1

# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------
_LOG_FILE="" # set by log_init; empty = file logging disabled

# ---------------------------------------------------------------------------
# Color setup (uses tput; disabled when NO_COLOR or non-tty stdout)
# ---------------------------------------------------------------------------
_log_setup_colors() {
  if [[ -n ${NO_COLOR:-} ]] || ! [[ -t 1 ]]; then
    _C_RESET="" _C_INFO="" _C_OK="" _C_WARN="" _C_ERROR="" _C_DEBUG=""
  else
    _C_RESET="$(tput sgr0 2>/dev/null || true)"
    _C_INFO="$(tput setaf 4 2>/dev/null || true)"  # blue
    _C_OK="$(tput setaf 2 2>/dev/null || true)"    # green
    _C_WARN="$(tput setaf 3 2>/dev/null || true)"  # yellow
    _C_ERROR="$(tput setaf 1 2>/dev/null || true)" # red
    _C_DEBUG="$(tput setaf 5 2>/dev/null || true)" # magenta
  fi
}
_log_setup_colors

# ---------------------------------------------------------------------------
# log_init — open a per-run log file under $ARCHINIT_STATE/logs/
# Call this at the start of any mutating command (install, update, restore).
# ---------------------------------------------------------------------------
log_init() {
  local log_dir="${ARCHINIT_STATE}/logs"
  mkdir -p "$log_dir"
  local ts
  ts="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
  _LOG_FILE="${log_dir}/${ts}.log"
  : >"$_LOG_FILE"
  # Update latest.log symlink
  ln -sfn "${ts}.log" "${log_dir}/latest.log"
}

# ---------------------------------------------------------------------------
# Internal write to file (uncolored, timestamped)
# ---------------------------------------------------------------------------
_log_to_file() {
  local level="$1"
  local msg="$2"
  if [[ -n $_LOG_FILE ]]; then
    printf '[%s] [%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$level" "$msg" >>"$_LOG_FILE"
  fi
}

# ---------------------------------------------------------------------------
# Public logging functions
# ---------------------------------------------------------------------------

log_info() {
  [[ -n ${QUIET:-} ]] && {
    _log_to_file INFO "$*"
    return 0
  }
  printf '%b[INFO]%b  %s\n' "${_C_INFO}" "${_C_RESET}" "$*"
  _log_to_file INFO "$*"
}

log_ok() {
  [[ -n ${QUIET:-} ]] && {
    _log_to_file OK "$*"
    return 0
  }
  printf '%b[ OK ]%b  %s\n' "${_C_OK}" "${_C_RESET}" "$*"
  _log_to_file OK "$*"
}

log_warn() {
  printf '%b[WARN]%b  %s\n' "${_C_WARN}" "${_C_RESET}" "$*" >&2
  _log_to_file WARN "$*"
}

log_error() {
  printf '%b[ERR ]%b  %s\n' "${_C_ERROR}" "${_C_RESET}" "$*" >&2
  _log_to_file ERROR "$*"
}

log_debug() {
  [[ -z ${VERBOSE:-} ]] && {
    _log_to_file DEBUG "$*"
    return 0
  }
  printf '%b[DBG ]%b  %s\n' "${_C_DEBUG}" "${_C_RESET}" "$*"
  _log_to_file DEBUG "$*"
}
