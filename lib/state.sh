#!/usr/bin/env bash
# lib/state.sh — module completion markers (no jq dependency)
# Requires: lib/core.sh sourced first (ARCHINIT_STATE).

[[ -n ${_ARCHINIT_STATE:-} ]] && return 0
_ARCHINIT_STATE=1

# shellcheck disable=SC2153  # ARCHINIT_STATE is exported by lib/core.sh
_STATE_DIR="${ARCHINIT_STATE}/.state"

# _state_ensure_dir — create the state directory if needed
_state_ensure_dir() {
  mkdir -p "$_STATE_DIR"
}

# state_mark NAME — record that module NAME completed successfully
state_mark() {
  local name="$1"
  _state_ensure_dir
  touch "${_STATE_DIR}/${name}.done"
}

# state_done NAME — return 0 if the completion marker exists
state_done() {
  local name="$1"
  [[ -f "${_STATE_DIR}/${name}.done" ]]
}

# state_clear NAME — remove the completion marker for NAME
state_clear() {
  local name="$1"
  rm -f "${_STATE_DIR}/${name}.done"
}
