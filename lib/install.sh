#!/usr/bin/env bash
# lib/install.sh — shared module runner (topological sort + install loop)
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

# _find_module_file NAME — print path to module.sh for a given module name
_find_module_file() {
  local name="$1"
  local f
  for f in "${ARCHINIT_HOME}/modules"/*/module.sh; do
    local n
    n="$(bash -c "
      ARCHINIT_HOME='${ARCHINIT_HOME}'
      source '${ARCHINIT_HOME}/lib/core.sh' 2>/dev/null || true
      source '${f}' 2>/dev/null || true
      module_name
    " 2>/dev/null || true)"
    if [[ $n == "$name" ]]; then
      echo "$f"
      return 0
    fi
  done
  return 1
}

# _all_module_names — list all module names in numeric directory order
_all_module_names() {
  local f
  while IFS= read -r f; do
    bash -c "
      ARCHINIT_HOME='${ARCHINIT_HOME}'
      source '${ARCHINIT_HOME}/lib/core.sh' 2>/dev/null || true
      source '${f}' 2>/dev/null || true
      module_name
    " 2>/dev/null || true
  done < <(find "${ARCHINIT_HOME}/modules" -maxdepth 2 -name "module.sh" | sort)
}

# _module_requires NAME — print space-separated dependency names for a module
_module_requires() {
  local name="$1"
  local f
  f="$(_find_module_file "$name")" || { echo ""; return 0; }
  bash -c "
    ARCHINIT_HOME='${ARCHINIT_HOME}'
    source '${ARCHINIT_HOME}/lib/core.sh' 2>/dev/null || true
    source '${f}' 2>/dev/null || true
    module_requires
  " 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Topological sort (DFS, cycle detection)
# ---------------------------------------------------------------------------

# _topo_sort NAMES... — print module names in dependency-first order
# Sets global array _TOPO_SORTED; returns non-zero if cycle detected.
_topo_sort() {
  local -a input=("$@")
  _TOPO_SORTED=()
  local -A visited=()    # 0=unvisited, 1=in-progress, 2=done

  _visit() {
    local node="$1"
    case "${visited[$node]:-0}" in
      2) return 0 ;;
      1) die "Module dependency cycle detected at: ${node}" ;;
    esac
    visited[$node]=1

    local deps dep
    deps="$(_module_requires "$node")"
    for dep in $deps; do
      _visit "$dep"
    done

    visited[$node]=2
    _TOPO_SORTED+=("$node")
  }

  local m
  for m in "${input[@]}"; do
    _visit "$m"
  done
}

# ---------------------------------------------------------------------------
# run_modules NAMES... — resolve deps and install in order
# ---------------------------------------------------------------------------
run_modules() {
  local -a requested=("$@")

  # If "all" is the sole argument, expand to all modules
  if [[ ${#requested[@]} -eq 1 && ${requested[0]} == "all" ]]; then
    mapfile -t requested < <(_all_module_names)
  fi

  local -a _TOPO_SORTED=()
  _topo_sort "${requested[@]}"

  local failed=0

  for module_name in "${_TOPO_SORTED[@]}"; do
    local module_file
    if ! module_file="$(_find_module_file "$module_name")"; then
      log_error "Module not found: ${module_name}"
      ((failed++)) || true
      continue
    fi

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
