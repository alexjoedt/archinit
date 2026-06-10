#!/usr/bin/env bash
# shell/archinit.sh — shell hook: PATH setup + throttled auto-update
# Sourced from ~/.zshrc / ~/.bashrc; does nothing in non-interactive shells.

# Only run in interactive shells
[[ $- == *i* ]] || return 0

# ---------------------------------------------------------------------------
# PATH — prepend archinit bin (guard against duplicates)
# ---------------------------------------------------------------------------
_archinit_bin="${HOME}/.archinit/bin"
if [[ -d $_archinit_bin ]] && [[ ":${PATH}:" != *":${_archinit_bin}:"* ]]; then
  export PATH="${_archinit_bin}:${PATH}"
fi
unset _archinit_bin

# ---------------------------------------------------------------------------
# Throttled auto-update (at most once per UPDATE_INTERVAL_HOURS)
# ---------------------------------------------------------------------------
_archinit_maybe_update() {
  local archinit_home="${HOME}/.archinit"
  local state_dir="${XDG_STATE_HOME:-${HOME}/.local/state}/archinit"
  local stamp="${state_dir}/.last_update"
  local interval_hours=24

  # Read override from defaults.conf if available
  local conf="${archinit_home}/config/defaults.conf"
  if [[ -f $conf ]]; then
    local _interval
    _interval="$(grep -E '^UPDATE_INTERVAL_HOURS=' "$conf" | head -1 | cut -d= -f2)"
    [[ -n $_interval ]] && interval_hours="$_interval"
  fi

  # Check if update is due
  local now elapsed=999999
  now="$(date +%s)"
  if [[ -f $stamp ]]; then
    local mtime
    mtime="$(date -r "$stamp" +%s 2>/dev/null || stat -c %Y "$stamp" 2>/dev/null || echo "0")"
    elapsed=$(((now - mtime) / 3600))
  fi

  if ((elapsed >= interval_hours)); then
    # Run update in background; never block the prompt
    local log_dir="${state_dir}/logs"
    mkdir -p "$log_dir" 2>/dev/null || true
    (
      "${archinit_home}/bin/archinit" update --no-modules --no-snapshot \
        >>"${log_dir}/autoupdate.log" 2>&1
    ) &
    disown $! 2>/dev/null || true
  fi
}

# Only attempt auto-update if archinit is installed
if [[ -x "${HOME}/.archinit/bin/archinit" ]]; then
  _archinit_maybe_update
fi
unset -f _archinit_maybe_update
