#!/usr/bin/env bash
# cmd/list.sh — list modules with class and status

# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_LOG:-} ]] || source "${ARCHINIT_HOME}/lib/log.sh"

cmd_list_help() {
  cat <<'EOF'
Usage: archinit list

List all available modules with their class, description, and current status.
Status is determined by running module_check in a subshell (read-only).
EOF
}

cmd_list() {
  # Print header
  printf '%-20s %-12s %-8s %s\n' "MODULE" "CLASS" "STATUS" "DESCRIPTION"
  printf '%s\n' "$(printf '%.0s-' {1..72})"

  # Find modules in numeric order
  local module_dirs
  mapfile -t module_dirs < <(find "${ARCHINIT_HOME}/modules" -maxdepth 2 -name "module.sh" | sort)

  for module_file in "${module_dirs[@]}"; do
    # Source in a subshell to avoid polluting current env
    local name class describe status
    name="$(bash -c "
      ARCHINIT_HOME='${ARCHINIT_HOME}'
      # shellcheck source=/dev/null
      source '${ARCHINIT_HOME}/lib/core.sh' 2>/dev/null || true
      source '${module_file}' 2>/dev/null
      module_name
    " 2>/dev/null || true)"

    class="$(bash -c "
      ARCHINIT_HOME='${ARCHINIT_HOME}'
      source '${ARCHINIT_HOME}/lib/core.sh' 2>/dev/null || true
      source '${module_file}' 2>/dev/null
      module_class
    " 2>/dev/null || true)"

    describe="$(bash -c "
      ARCHINIT_HOME='${ARCHINIT_HOME}'
      source '${ARCHINIT_HOME}/lib/core.sh' 2>/dev/null || true
      source '${module_file}' 2>/dev/null
      module_describe
    " 2>/dev/null || true)"

    if bash -c "
      ARCHINIT_HOME='${ARCHINIT_HOME}'
      source '${ARCHINIT_HOME}/lib/core.sh' 2>/dev/null || true
      source '${module_file}' 2>/dev/null
      module_check
    " &>/dev/null 2>&1; then
      status="ok"
    else
      status="pending"
    fi

    [[ -z $name ]] && continue
    printf '%-20s %-12s %-8s %s\n' "$name" "$class" "$status" "$describe"
  done
}
