#!/usr/bin/env bash
# lib/install.sh — module runner
# Module names are derived from the directory name by stripping the NN- prefix.
# Execution order is determined by the numeric prefix (sort order).
# Sourcing-safe: double-source guard at top.

[[ -n ${_ARCHINIT_INSTALL:-} ]] && return 0
_ARCHINIT_INSTALL=1

# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_CORE:-} ]] || source "${ARCHINIT_HOME}/lib/core.sh"
# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_LOG:-} ]] || source "${ARCHINIT_HOME}/lib/log.sh"
# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_STATE:-} ]] || source "${ARCHINIT_HOME}/lib/state.sh"

# ---------------------------------------------------------------------------
# Module discovery helpers
# ---------------------------------------------------------------------------

# _module_name_from_path PATH — modules/35-git/module.sh → git
_module_name_from_path() {
  local dir; dir="$(dirname "$1")"
  local base; base="${dir##*/}"
  echo "${base#*-}"
}

# _find_module_file NAME — path to module.sh, no subshells
_find_module_file() {
  local name="$1" f
  for f in "${ARCHINIT_HOME}/modules"/*/module.sh; do
    [[ "$(_module_name_from_path "$f")" == "$name" ]] && echo "$f" && return 0
  done
  return 1
}

# _all_module_files — module.sh paths in numeric directory order
_all_module_files() {
  find "${ARCHINIT_HOME}/modules" -maxdepth 2 -name "module.sh" | sort
}

# ---------------------------------------------------------------------------
# run_modules NAMES... — install modules in NN- prefix order
# ---------------------------------------------------------------------------
run_modules() {
  local -a requested=("$@")
  local -a module_files=()

  if [[ ${#requested[@]} -eq 1 && ${requested[0]} == "all" ]]; then
    mapfile -t module_files < <(_all_module_files)
  else
    # Resolve requested names to paths, preserving sort order
    local -a all_files; mapfile -t all_files < <(_all_module_files)
    local f name req
    for f in "${all_files[@]}"; do
      name="$(_module_name_from_path "$f")"
      for req in "${requested[@]}"; do
        if [[ $name == "$req" ]]; then
          module_files+=("$f")
          break
        fi
      done
    done
    # Warn about any requested names that were not found
    for req in "${requested[@]}"; do
      local found=0
      for f in "${module_files[@]+"${module_files[@]}"}"; do
        [[ "$(_module_name_from_path "$f")" == "$req" ]] && found=1 && break
      done
      ((found == 0)) && log_error "Module not found: ${req}"
    done
  fi

  local failed=0

  for module_file in "${module_files[@]+"${module_files[@]}"}"; do
    local module_name
    module_name="$(_module_name_from_path "$module_file")"

    log_info "Module: ${module_name}"

    # Run module_check in subshell to test idempotency
    if bash -c "
      ARCHINIT_HOME='${ARCHINIT_HOME}'
      source '${ARCHINIT_HOME}/lib/core.sh' 2>/dev/null
      source '${module_file}' 2>/dev/null
      module_check
    " &>/dev/null 2>&1; then
      if [[ -z ${FORCE:-} ]]; then
        log_info "  already satisfied — skipping (use --force to re-run)"
        continue
      fi
    fi

    # Run module_install in subshell
    if bash -c "
      ARCHINIT_HOME='${ARCHINIT_HOME}'
      DRY_RUN='${DRY_RUN:-}'
      ASSUME_YES='${ASSUME_YES:-}'
      VERBOSE='${VERBOSE:-}'
      QUIET='${QUIET:-}'
      NO_COLOR='${NO_COLOR:-}'
      FORCE='${FORCE:-}'
      export DRY_RUN ASSUME_YES VERBOSE QUIET NO_COLOR FORCE
      source '${ARCHINIT_HOME}/lib/core.sh'
      source '${module_file}'
      module_install
    "; then
      state_mark "$module_name"
      log_ok "  ${module_name}: done"
    else
      log_error "  ${module_name}: FAILED"
      ((failed++)) || true
    fi
  done

  if ((failed > 0)); then
    log_error "${failed} module(s) failed"
    return 1
  fi
  return 0
}
