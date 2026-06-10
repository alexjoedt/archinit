#!/usr/bin/env bash
# lib/ui.sh — TUI abstraction: gum -> whiptail -> dialog -> plain text
# Requires: lib/core.sh, lib/log.sh, lib/os.sh sourced first (or auto-sourced).

[[ -n ${_ARCHINIT_UI:-} ]] && return 0
_ARCHINIT_UI=1

# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_OS:-} ]] || source "${ARCHINIT_HOME}/lib/os.sh"

# ---------------------------------------------------------------------------
# Backend detection (cached)
# ---------------------------------------------------------------------------
_UI_BACKEND=""

_ui_detect_backend() {
  [[ -n $_UI_BACKEND ]] && return 0
  if has_cmd gum; then
    _UI_BACKEND="gum"
  elif has_cmd whiptail; then
    _UI_BACKEND="whiptail"
  elif has_cmd dialog; then
    _UI_BACKEND="dialog"
  else
    _UI_BACKEND="text"
  fi
}

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

  _ui_detect_backend
  case $_UI_BACKEND in
    gum)
      gum confirm "$msg"
      ;;
    whiptail)
      whiptail --yesno "$msg" 8 60
      ;;
    dialog)
      dialog --yesno "$msg" 8 60
      ;;
    *)
      # Plain text fallback
      local answer
      printf '%s [y/N] ' "$msg"
      read -r answer
      [[ ${answer,,} == "y" || ${answer,,} == "yes" ]]
      ;;
  esac
}

# ---------------------------------------------------------------------------
# ui_menu TITLE ITEM... — single-select menu; prints chosen item to stdout
# ---------------------------------------------------------------------------
ui_menu() {
  local title="$1"
  shift
  local -a items=("$@")

  _ui_detect_backend
  case $_UI_BACKEND in
    gum)
      printf '%s\n' "${items[@]}" | gum choose --header "$title"
      ;;
    whiptail | dialog)
      local -a menu_args=()
      local i=1
      local item
      for item in "${items[@]}"; do
        menu_args+=("$i" "$item")
        ((i++))
      done
      local choice
      choice=$("$_UI_BACKEND" --menu "$title" 20 60 "${#items[@]}" "${menu_args[@]}" 3>&1 1>&2 2>&3)
      # Convert index back to item name
      echo "${items[$((choice - 1))]}"
      ;;
    *)
      # Plain text fallback
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
      ;;
  esac
}

# ---------------------------------------------------------------------------
# ui_choose_multi TITLE ITEM... — multi-select; prints one chosen item per line
# ---------------------------------------------------------------------------
ui_choose_multi() {
  local title="$1"
  shift
  local -a items=("$@")

  _ui_detect_backend
  case $_UI_BACKEND in
    gum)
      printf '%s\n' "${items[@]}" | gum choose --no-limit --header "$title"
      ;;
    whiptail | dialog)
      local -a menu_args=()
      local item
      for item in "${items[@]}"; do
        menu_args+=("$item" "" "OFF")
      done
      local choices
      choices=$("$_UI_BACKEND" --checklist "$title" 20 60 "${#items[@]}" "${menu_args[@]}" 3>&1 1>&2 2>&3)
      # whiptail/dialog returns space-separated quoted items; eval expands them
      local -a selected
      eval "selected=($choices)"
      printf '%s\n' "${selected[@]}"
      ;;
    *)
      # Plain text fallback
      local i=1 item
      echo "$title"
      for item in "${items[@]}"; do
        printf '  %d) %s\n' "$i" "$item"
        ((i++))
      done
      printf 'Select (space-separated numbers): '
      local input
      read -r input
      local num
      for num in $input; do
        echo "${items[$((num - 1))]}"
      done
      ;;
  esac
}
