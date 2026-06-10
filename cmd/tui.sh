#!/usr/bin/env bash
# cmd/tui.sh — interactive module selector

# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_LOG:-} ]] || source "${ARCHINIT_HOME}/lib/log.sh"
# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_UI:-} ]] || source "${ARCHINIT_HOME}/lib/ui.sh"
# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_INSTALL:-} ]] || source "${ARCHINIT_HOME}/lib/install.sh"

cmd_tui_help() {
  cat <<'EOF'
Usage: archinit tui

Launch the interactive module selector. Choose modules to install using
the TUI (gum, whiptail, or dialog — whichever is available), then archinit
installs the selected modules in dependency order.
EOF
}

cmd_tui() {
  # Collect all module names and their descriptions; pre-select pending ones
  local -a items=()
  local -a pending=()

  local module_file name describe
  while IFS= read -r module_file; do
    name="$(bash -c "
      ARCHINIT_HOME='${ARCHINIT_HOME}'
      source '${ARCHINIT_HOME}/lib/core.sh' 2>/dev/null || true
      source '${module_file}' 2>/dev/null || true
      module_name
    " 2>/dev/null || true)"
    describe="$(bash -c "
      ARCHINIT_HOME='${ARCHINIT_HOME}'
      source '${ARCHINIT_HOME}/lib/core.sh' 2>/dev/null || true
      source '${module_file}' 2>/dev/null || true
      module_describe
    " 2>/dev/null || true)"
    [[ -z $name ]] && continue

    items+=("$name" "$describe")

    if ! bash -c "
      ARCHINIT_HOME='${ARCHINIT_HOME}'
      source '${ARCHINIT_HOME}/lib/core.sh' 2>/dev/null
      source '${module_file}' 2>/dev/null
      module_check
    " &>/dev/null 2>&1; then
      pending+=("$name")
    fi
  done < <(find "${ARCHINIT_HOME}/modules" -maxdepth 2 -name "module.sh" | sort)

  if [[ ${#items[@]} -eq 0 ]]; then
    log_error "No modules found in ${ARCHINIT_HOME}/modules"
    return 1
  fi

  local selected
  selected="$(ui_choose_multi "Select modules to install (pending pre-selected)" "${items[@]}")"

  if [[ -z $selected ]]; then
    log_info "No modules selected; exiting"
    return 0
  fi

  log_init

  # selected is newline- or space-separated; convert to array
  local -a selected_arr
  read -ra selected_arr <<<"$selected"

  run_modules "${selected_arr[@]}"
}
