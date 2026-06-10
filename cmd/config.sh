#!/usr/bin/env bash
# cmd/config.sh — view/set archinit configuration keys

# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_LOG:-} ]] || source "${ARCHINIT_HOME}/lib/log.sh"
# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_CONFIG:-} ]] || source "${ARCHINIT_HOME}/lib/config.sh"

cmd_config_help() {
  cat <<'EOF'
Usage:
  archinit config                    List all resolved config keys and values
  archinit config <key>              Print value of a single key
  archinit config <key> <value>      Set a key in config.local
  archinit config --unset <key>      Remove a key from config.local

config.local is located at $ARCHINIT_HOME/config.local.
Shipped defaults.conf is never modified.

Known keys: see config/defaults.conf
EOF
}

cmd_config() {
  local unset_key=""

  # Handle --unset flag
  if [[ "${1:-}" == "--unset" ]]; then
    unset_key="${2:?'archinit config --unset requires a KEY argument'}"
    config_unset "$unset_key"
    log_ok "config: unset ${unset_key}"
    return 0
  fi

  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cmd_config_help
    return 0
  fi

  local key="${1:-}"
  local value="${2:-__unset__}"

  if [[ -z $key ]]; then
    # List all resolved config keys from defaults.conf
    local defaults="${ARCHINIT_HOME}/config/defaults.conf"
    [[ -f $defaults ]] || die "config/defaults.conf not found"
    echo "# archinit resolved configuration (config.local overrides defaults.conf)"
    while IFS='=' read -r k _; do
      [[ $k =~ ^[[:space:]]*# ]] && continue
      [[ -z $k ]] && continue
      # Strip leading/trailing whitespace
      k="${k#"${k%%[![:space:]]*}"}"
      k="${k%"${k##*[![:space:]]}"}"
      [[ -z $k ]] && continue
      printf '%s=%s\n' "$k" "$(config_get "$k")"
    done < "$defaults"
    return 0
  fi

  if [[ $value == "__unset__" ]]; then
    # Print single key
    local v
    v="$(config_get "$key")"
    if [[ -z $v ]]; then
      log_warn "config: key '${key}' is empty or not set"
    else
      echo "$v"
    fi
    return 0
  fi

  # Set a key
  config_set "$key" "$value"
  log_ok "config: set ${key}=${value}"
}
