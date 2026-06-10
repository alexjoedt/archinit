#!/usr/bin/env bash
# install.sh — archinit bootstrap installer
# Usage: curl -fsSL https://raw.githubusercontent.com/.../install.sh | bash
#
# IMPORTANT: entire body is wrapped in main() so a truncated pipe download
# cannot execute a half-script.

set -euo pipefail
IFS=$'\n\t'

ARCHINIT_REPO="${ARCHINIT_REPO:-https://github.com/alexjoedt/archinit.git}"
ARCHINIT_HOME="${ARCHINIT_HOME:-$HOME/.archinit}"

# ---------------------------------------------------------------------------
main() {
  # --- OS check ---
  if [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    source /etc/os-release
    if [[ ${ID:-} != "arch" ]]; then
      echo "archinit: this installer is designed for Arch Linux (detected: ${ID:-unknown})" >&2
      exit 1
    fi
  else
    echo "archinit: cannot detect OS (/etc/os-release missing)" >&2
    exit 1
  fi

  # --- Ensure git ---
  if ! command -v git &>/dev/null; then
    echo "archinit: git not found; installing..." >&2
    sudo pacman -S --needed --noconfirm git
  fi

  # --- Clone or update ---
  if [[ -d "${ARCHINIT_HOME}/.git" ]]; then
    echo "archinit: updating existing clone at ${ARCHINIT_HOME}..."
    git -C "${ARCHINIT_HOME}" pull --ff-only
  else
    echo "archinit: cloning to ${ARCHINIT_HOME}..."
    git clone --depth=1 "${ARCHINIT_REPO}" "${ARCHINIT_HOME}"
  fi

  # Make entrypoint executable (absolute path post-clone)
  chmod +x "${ARCHINIT_HOME}/bin/archinit"

  # --- Add shell hook (idempotent: skip if already present) ---
  local hook_line="source \"\$HOME/.archinit/shell/archinit.sh\""
  local rc_file

  for rc_file in "${HOME}/.zshrc" "${HOME}/.bashrc"; do
    if [[ -f $rc_file ]] && grep -qF "archinit/shell/archinit.sh" "$rc_file"; then
      echo "archinit: shell hook already present in ${rc_file}"
    elif [[ -f $rc_file ]]; then
      printf '\n# archinit\n%s\n' "$hook_line" >>"$rc_file"
      echo "archinit: added shell hook to ${rc_file}"
    fi
  done

  echo ""
  echo "archinit installed successfully!"
  echo ""
  echo "Next steps:"
  echo "  1. Open a new shell (or run: source ~/.archinit/shell/archinit.sh)"
  echo "  2. Run: archinit        # opens the interactive TUI"
  echo "     or:  archinit install # installs all default modules"
}

main "$@"
