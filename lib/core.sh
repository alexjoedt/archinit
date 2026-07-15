#!/usr/bin/env bash
# lib/core.sh — strict mode, guards, globals, and core helpers
# Sourcing-safe: double-source guard at top.

[[ -n ${_ARCHINIT_CORE:-} ]] && return 0
_ARCHINIT_CORE=1

# Bash version guard (must come before set -u so BASH_VERSINFO is always set)
if ((BASH_VERSINFO[0] < 4)); then
  echo "archinit: bash >= 4 required (got ${BASH_VERSION})" >&2
  exit 1
fi

set -euo pipefail
IFS=$'\n\t'

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
ARCHINIT_HOME="${ARCHINIT_HOME:-$HOME/.archinit}"
ARCHINIT_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/archinit"

export ARCHINIT_HOME ARCHINIT_STATE

# ---------------------------------------------------------------------------
# Global flags (set by bin/archinit arg parser; default empty = false)
# ---------------------------------------------------------------------------
DRY_RUN="${DRY_RUN:-}"
ASSUME_YES="${ASSUME_YES:-}"
VERBOSE="${VERBOSE:-}"
QUIET="${QUIET:-}"
NO_COLOR="${NO_COLOR:-}"

export DRY_RUN ASSUME_YES VERBOSE QUIET NO_COLOR

# ---------------------------------------------------------------------------
# ERR trap — print failing command + line number
# ---------------------------------------------------------------------------
_archinit_err_trap() {
  local exit_code=$?
  echo "archinit: error on line ${BASH_LINENO[0]}: ${BASH_COMMAND} (exit ${exit_code})" >&2
}
trap '_archinit_err_trap' ERR

# ---------------------------------------------------------------------------
# Interrupt handling — Ctrl-C (SIGINT) / SIGTERM must stop the script entirely,
# including any background helpers (e.g. the sudo keepalive loop).
# We disarm ERR (so the abort isn't reported as a command failure), run cleanup,
# then re-raise the signal so the exit status is the conventional 128+signo.
# ---------------------------------------------------------------------------
_archinit_interrupt() {
  local sig="$1"
  # Restore default handlers to prevent re-entry / recursion
  trap - INT TERM ERR
  _archinit_cleanup_sudo
  printf '\n' >&2
  echo "archinit: aborted (received SIG${sig})" >&2
  # Re-raise on self so the shell terminates with status 128+signo
  kill -s "$sig" "$$"
  # Fallback if the signal is somehow swallowed
  exit 130
}
trap '_archinit_interrupt INT' INT
trap '_archinit_interrupt TERM' TERM

# ---------------------------------------------------------------------------
# Core helpers
# ---------------------------------------------------------------------------

# die MESSAGE [EXIT_CODE]
die() {
  echo "archinit: fatal: $1" >&2
  exit "${2:-1}"
}

# require_cmd CMD [MESSAGE]
require_cmd() {
  command -v "$1" &>/dev/null || die "${2:-command \"$1\" not found}"
}

# is_root — returns 0 if running as root
is_root() {
  [[ $EUID -eq 0 ]]
}

# as_root CMD [ARGS...] — run a command as root; use sudo only when not root
as_root() {
  if is_root; then
    "$@"
  else
    sudo "$@"
  fi
}

# run CMD [ARGS...] — echo in dry-run mode; execute otherwise
run() {
  if [[ -n $DRY_RUN ]]; then
    echo "[dry-run] $*"
  else
    "$@"
  fi
}

# ---------------------------------------------------------------------------
# sudo keepalive — call once at the start of a mutating operation.
# Refreshes sudo credentials in background so long installs don't prompt.
# Killed automatically on EXIT.
# ---------------------------------------------------------------------------
_SUDO_KEEPALIVE_PID=""

sudo_keepalive() {
  # Do nothing if already root or in dry-run
  if is_root || [[ -n $DRY_RUN ]]; then
    return 0
  fi
  # Validate once up front
  sudo -v
  # Background loop: refresh every 50 s (sudo timeout is typically 300 s)
  (
    # Inherit no traps: a signal should just terminate this helper
    trap - INT TERM ERR EXIT
    while true; do
      sleep 50
      sudo -v
    done
  ) &
  _SUDO_KEEPALIVE_PID=$!
  # Ensure the loop is killed when the script exits
  trap '_archinit_cleanup_sudo' EXIT
}

_archinit_cleanup_sudo() {
  if [[ -n ${_SUDO_KEEPALIVE_PID:-} ]]; then
    kill "$_SUDO_KEEPALIVE_PID" 2>/dev/null || true
    _SUDO_KEEPALIVE_PID=""
  fi
}
