#!/usr/bin/env bash
# lib/config.sh — load and merge archinit configuration
# Sourcing-safe: double-source guard at top.

[[ -n ${_ARCHINIT_CONFIG:-} ]] && return 0
_ARCHINIT_CONFIG=1

# core.sh must be loaded first (provides ARCHINIT_HOME, die)
# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_CORE:-} ]] || source "$(dirname "${BASH_SOURCE[0]}")/core.sh"

# ---------------------------------------------------------------------------
# Load configuration
# ---------------------------------------------------------------------------

# config_load — source defaults then optional config.local override
config_load() {
  local defaults="${ARCHINIT_HOME}/config/defaults.conf"
  local local_conf="${ARCHINIT_HOME}/config.local"
  local xdg_conf="${XDG_CONFIG_HOME:-$HOME/.config}/archinit/config.local"

  if [[ -f $defaults ]]; then
    # shellcheck source=/dev/null
    source "$defaults"
  else
    die "config/defaults.conf not found in ARCHINIT_HOME=${ARCHINIT_HOME}"
  fi

  # User override: prefer $ARCHINIT_HOME/config.local, then XDG location
  if [[ -f $local_conf ]]; then
    # shellcheck source=/dev/null
    source "$local_conf"
  elif [[ -f $xdg_conf ]]; then
    # shellcheck source=/dev/null
    source "$xdg_conf"
  fi
  # Missing local file is not an error — defaults are sufficient
}

# config_get KEY — print the value of a config key (post-load)
config_get() {
  local key="${1:?config_get: KEY required}"
  # Use indirect variable expansion
  echo "${!key:-}"
}

# config_set KEY VALUE [FILE] — write or update a key in config.local
# FILE defaults to $ARCHINIT_HOME/config.local
config_set() {
  local key="${1:?config_set: KEY required}"
  local value="${2?config_set: VALUE required}"
  local file="${3:-${ARCHINIT_HOME}/config.local}"

  # Validate key is a known config key (present in defaults.conf)
  local defaults="${ARCHINIT_HOME}/config/defaults.conf"
  if [[ -f $defaults ]] && ! grep -qE "^${key}=" "$defaults"; then
    log_warn "config_set: unknown config key '${key}'"
  fi

  if [[ -f $file ]] && grep -qE "^${key}=" "$file"; then
    # Update existing line (BSD + GNU sed compatible via temp file)
    local tmp
    tmp="$(mktemp)"
    sed "s|^${key}=.*|${key}=${value}|" "$file" >"$tmp" && mv "$tmp" "$file"
  else
    # Append new key
    printf '%s=%s\n' "$key" "$value" >>"$file"
  fi
}

# config_unset KEY [FILE] — remove a key from config.local
config_unset() {
  local key="${1:?config_unset: KEY required}"
  local file="${2:-${ARCHINIT_HOME}/config.local}"

  [[ -f $file ]] || return 0

  local tmp
  tmp="$(mktemp)"
  grep -vE "^${key}=" "$file" >"$tmp" && mv "$tmp" "$file"
}

# Load config immediately when this library is sourced
config_load
