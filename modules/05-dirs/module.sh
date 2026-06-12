#!/usr/bin/env bash
# modules/05-dirs/module.sh — create standard workspace directories
#
# Default dirs are defined below. Override or extend via USER_DIRS in config.local:
#   USER_DIRS="~/projects ~/work/clients ~/.local/bin"
# Tilde (~) and $HOME are expanded. Space-separated; quote paths with spaces.

# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_CORE:-} ]] || source "${ARCHINIT_HOME}/lib/core.sh"
# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_LOG:-} ]] || source "${ARCHINIT_HOME}/lib/log.sh"
# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_FS:-} ]] || source "${ARCHINIT_HOME}/lib/fs.sh"
# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_CONFIG:-} ]] || source "${ARCHINIT_HOME}/lib/config.sh"

module_name()     { echo "dirs"; }
module_class()    { echo "base"; }
module_describe() { echo "Create standard workspace and local bin directories"; }
module_requires() { echo ""; }

# Default directory list — override/extend with USER_DIRS in config.local
_DEFAULT_DIRS=(
  "$HOME/workspace/github"
  "$HOME/tmp"
  "$HOME/.local/bin"
  "$HOME/.config"
)

# _expand_dirs — merge defaults with USER_DIRS config, expand ~ and $HOME
_expand_dirs() {
  local -a all=("${_DEFAULT_DIRS[@]}")

  local extra
  extra="$(config_get USER_DIRS)"
  if [[ -n $extra ]]; then
    local d
    for d in $extra; do
      # Expand leading ~ to $HOME
      all+=("${d/#\~/$HOME}")
    done
  fi

  # Print deduplicated list
  local -A seen=()
  for d in "${all[@]}"; do
    [[ -n ${seen[$d]:-} ]] && continue
    seen[$d]=1
    echo "$d"
  done
}

module_check() {
  local d
  while IFS= read -r d; do
    [[ -d $d ]] || return 1
  done < <(_expand_dirs)
  return 0
}

module_install() {
  local d
  while IFS= read -r d; do
    if [[ -d $d ]]; then
      log_debug "dirs: already exists: $d"
    else
      ensure_dir "$d"
      log_ok "dirs: created $d"
    fi
  done < <(_expand_dirs)
}
