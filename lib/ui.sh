#!/usr/bin/env bash
# lib/ui.sh — TUI abstraction: gum → plain text
# gum is installed via config/packages/base.txt on first run.
# Plain text fallback covers the bootstrap window before gum is available.

[[ -n ${_ARCHINIT_UI:-} ]] && return 0
_ARCHINIT_UI=1

# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_LOG:-} ]] || source "${ARCHINIT_HOME}/lib/log.sh"
# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_OS:-} ]] || source "${ARCHINIT_HOME}/lib/os.sh"

# ---------------------------------------------------------------------------
# ui_confirm MSG — ask a yes/no question; return 0 for yes
# Respects ASSUME_YES: returns 0 without prompting.
# ---------------------------------------------------------------------------
ui_confirm() {
  local msg="$1"

  if [[ -n ${ASSUME_YES:-} ]]; then
    log_debug "ui_confirm (assume-yes): $msg"
    return 0
  fi

  if has_cmd gum; then
    gum confirm "$msg"
    return
  fi

  # Plain text fallback — hang-safe: no TTY → treat as 'no'
  if [[ ! -t 0 ]]; then
    log_warn "ui_confirm: no TTY — treating as 'no': ${msg}"
    return 1
  fi
  local answer
  printf '%s [y/N] ' "$msg"
  read -r answer
  [[ ${answer,,} == "y" || ${answer,,} == "yes" ]]
}

# ---------------------------------------------------------------------------
# ui_menu TITLE ITEM... — single-select; prints chosen item to stdout
# ---------------------------------------------------------------------------
ui_menu() {
  local title="$1"
  shift
  local -a items=("$@")

  if has_cmd gum; then
    printf '%s\n' "${items[@]}" | gum choose --header "$title"
    return
  fi

  # Plain text fallback — hang-safe: no TTY → error
  if [[ ! -t 0 ]]; then
    log_warn "ui_menu: no TTY — cannot prompt for '${title}'"
    return 1
  fi
  local i=1 item
  echo "$title"
  for item in "${items[@]}"; do
    printf '  %d) %s\n' "$i" "$item"
    ((i++))
  done
  local choice
  printf 'Choose [1-%d]: ' "${#items[@]}"
  read -r choice
  echo "${items[$((choice - 1))]}"
}

# ---------------------------------------------------------------------------
# ui_choose_multi TITLE ITEM... — multi-select; prints one chosen item per line
# ---------------------------------------------------------------------------
ui_choose_multi() {
  local title="$1"
  shift
  local -a items=("$@")

  if has_cmd gum; then
    printf '%s\n' "${items[@]}" | gum choose --no-limit --header "$title"
    return
  fi

  # Plain text fallback — hang-safe: no TTY → error
  if [[ ! -t 0 ]]; then
    log_warn "ui_choose_multi: no TTY — cannot prompt for '${title}'"
    return 1
  fi
  local i=1 item
  echo "$title"
  for item in "${items[@]}"; do
    printf '  %d) %s\n' "$i" "$item"
    ((i++))
  done
  local input
  printf 'Select (space-separated numbers): '
  read -r input
  local num
  for num in $input; do
    echo "${items[$((num - 1))]}"
  done
}
