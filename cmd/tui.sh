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
  # Collect module names, descriptions, and pending state
  local -a names_arr=()
  local -a display_arr=()
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

    names_arr+=("$name")
    display_arr+=("${name} — ${describe}")

    if ! bash -c "
      ARCHINIT_HOME='${ARCHINIT_HOME}'
      source '${ARCHINIT_HOME}/lib/core.sh' 2>/dev/null
      source '${module_file}' 2>/dev/null
      module_check
    " &>/dev/null 2>&1; then
      pending+=("$name")
    fi
  done < <(find "${ARCHINIT_HOME}/modules" -maxdepth 2 -name "module.sh" | sort)

  if [[ ${#names_arr[@]} -eq 0 ]]; then
    log_error "No modules found in ${ARCHINIT_HOME}/modules"
    return 1
  fi

  local selected
  selected="$(ui_choose_multi "Select modules to install (pending pre-selected)" "${display_arr[@]}")"

  if [[ -z $selected ]]; then
    log_info "No modules selected; exiting"
    return 0
  fi

  log_init

  # Map selected display strings back to module names
  local -a selected_arr=()
  local line i
  while IFS= read -r line; do
    for i in "${!display_arr[@]}"; do
      if [[ "${display_arr[$i]}" == "$line" ]]; then
        selected_arr+=("${names_arr[$i]}")
        break
      fi
    done
  done <<<"$selected"

  # Inform the user if any explicitly selected modules are already satisfied
  local m module_file
  for m in "${selected_arr[@]}"; do
    module_file="$(_find_module_file "$m" 2>/dev/null || true)"
    [[ -z $module_file ]] && continue
    if bash -c "
      ARCHINIT_HOME='${ARCHINIT_HOME}'
      source '${ARCHINIT_HOME}/lib/core.sh' 2>/dev/null
      source '${module_file}' 2>/dev/null
      module_check
    " &>/dev/null 2>&1; then
      log_warn "Module '${m}' is already satisfied — use --force to re-run"
    fi
  done

  run_modules "${selected_arr[@]}"
}
