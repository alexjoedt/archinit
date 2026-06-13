#!/usr/bin/env bash
# install.sh — archinit bootstrap installer
# Usage: curl -fsSL https://raw.githubusercontent.com/.../install.sh | bash
#
# IMPORTANT: entire body is wrapped in main() so a truncated pipe download
# cannot execute a half-script.
#
# Environment overrides (skips the corresponding prompt):
#   GIT_USER_NAME, GIT_USER_EMAIL, DOTFILES_REPO, GIT_AUTH_METHOD
#
# Set ARCHINIT_SKIP_INSTALL=1 to clone and seed config without running install.

set -euo pipefail
IFS=$'\n\t'

ARCHINIT_REPO="${ARCHINIT_REPO:-https://github.com/alexjoedt/archinit.git}"
ARCHINIT_BRANCH="${ARCHINIT_BRANCH:-main}"
ARCHINIT_HOME="${ARCHINIT_HOME:-$HOME/.archinit}"

# ---------------------------------------------------------------------------
# _write_config KEY VALUE — append/replace a key in config.local (no deps)
# ---------------------------------------------------------------------------
_write_config() {
  local key="$1" value="$2"
  local config_file="${ARCHINIT_HOME}/config.local"
  [[ -f $config_file ]] || touch "$config_file"
  # Remove existing entry for this key
  local tmp
  tmp="$(mktemp)"
  grep -v "^${key}=" "$config_file" >"$tmp" || true
  mv "$tmp" "$config_file"
  # %q makes the value safe to re-source as bash (handles spaces, quotes, $, etc.)
  printf '%s=%q\n' "$key" "$value" >>"$config_file"
}

# ---------------------------------------------------------------------------
# _seed_config — optional prompts for personal values (curl-pipe-safe)
# ---------------------------------------------------------------------------
_seed_config() {
  # If /dev/tty is unavailable (non-interactive pipe), skip entirely
  if [[ ! -e /dev/tty ]]; then
    echo "archinit: no TTY available — skipping configuration prompts"
    echo "archinit: run 'archinit config KEY value' to set configuration later"
    return 0
  fi

  printf '\n%s\n' "archinit: Optional setup — press Enter to skip any prompt."
  printf '%s\n\n' "archinit: Values are saved to ${ARCHINIT_HOME}/config.local"

  local git_name git_email dotfiles_repo git_auth_method

  # Detect existing git identity in ~/.gitconfig — skip prompts if present
  local existing_git_name existing_git_email
  existing_git_name="$(git config --global user.name 2>/dev/null || true)"
  existing_git_email="$(git config --global user.email 2>/dev/null || true)"

  # GIT_USER_NAME
  if [[ -n ${GIT_USER_NAME:-} ]]; then
    git_name="$GIT_USER_NAME"
    printf 'archinit: GIT_USER_NAME="%s" (from environment)\n' "$git_name"
  elif [[ -n $existing_git_name ]]; then
    git_name="$existing_git_name"
    printf 'archinit: git user.name already set to "%s" — skipping\n' "$git_name"
  else
    printf 'Git user name       [Enter to skip]: ' >/dev/tty
    read -r git_name </dev/tty || true
  fi

  # GIT_USER_EMAIL
  if [[ -n ${GIT_USER_EMAIL:-} ]]; then
    git_email="$GIT_USER_EMAIL"
    printf 'archinit: GIT_USER_EMAIL="%s" (from environment)\n' "$git_email"
  elif [[ -n $existing_git_email ]]; then
    git_email="$existing_git_email"
    printf 'archinit: git user.email already set to "%s" — skipping\n' "$git_email"
  else
    printf 'Git user email      [Enter to skip]: ' >/dev/tty
    read -r git_email </dev/tty || true
  fi

  # DOTFILES_REPO
  if [[ -n ${DOTFILES_REPO:-} ]]; then
    dotfiles_repo="$DOTFILES_REPO"
    printf 'archinit: DOTFILES_REPO="%s" (from environment)\n' "$dotfiles_repo"
  else
    printf 'Dotfiles repo URL   [Enter to skip]: ' >/dev/tty
    read -r dotfiles_repo </dev/tty || true
  fi

  # GIT_AUTH_METHOD
  if [[ -n ${GIT_AUTH_METHOD:-} ]]; then
    git_auth_method="$GIT_AUTH_METHOD"
    printf 'archinit: GIT_AUTH_METHOD="%s" (from environment)\n' "$git_auth_method"
  elif [[ -s ${HOME}/.git-credentials ]] \
    || [[ -n "$(git config --global credential.helper 2>/dev/null || true)" ]] \
    || [[ -f ${HOME}/.ssh/id_ed25519 ]] || [[ -f ${HOME}/.ssh/id_rsa ]]; then
    git_auth_method="skip"
    printf 'archinit: git auth already configured — skipping\n'
  else
    printf 'Git auth method (ssh/token/skip) [Enter for ssh]: ' >/dev/tty
    read -r git_auth_method </dev/tty || true
    git_auth_method="${git_auth_method:-ssh}"
  fi

  printf '\n'

  # Write non-empty values to config.local
  [[ -n $git_name ]]      && _write_config GIT_USER_NAME  "$git_name"
  [[ -n $git_email ]]     && _write_config GIT_USER_EMAIL "$git_email"
  [[ -n $dotfiles_repo ]] && _write_config DOTFILES_REPO  "$dotfiles_repo"
  [[ $git_auth_method != "ssh" ]] \
    && _write_config GIT_AUTH_METHOD "$git_auth_method"

  echo "archinit: Configuration saved. Run 'archinit config' to view or change values."
}

# ---------------------------------------------------------------------------
main() {
  # --- OS check ---
  # if [[ -f /etc/os-release ]]; then
  #   # shellcheck source=/dev/null
  #   source /etc/os-release
  #   if [[ ${ID:-} != "arch" ]]; then
  #     echo "archinit: this installer is designed for Arch Linux (detected: ${ID:-unknown})" >&2
  #     exit 1
  #   fi
  # else
  #   echo "archinit: cannot detect OS (/etc/os-release missing)" >&2
  #   exit 1
  # fi

  # --- Ensure git ---
  if ! command -v git &>/dev/null; then
    echo "archinit: git not found; installing..." >&2
    sudo pacman -S --needed --noconfirm git
  fi

  # --- Clone or update ---
  if [[ -d "${ARCHINIT_HOME}/.git" ]]; then
    echo "archinit: updating existing clone at ${ARCHINIT_HOME}..."
    git -C "${ARCHINIT_HOME}" fetch origin
    git -C "${ARCHINIT_HOME}" checkout "${ARCHINIT_BRANCH}"
    git -C "${ARCHINIT_HOME}" pull --ff-only origin "${ARCHINIT_BRANCH}"
  else
    echo "archinit: using branch '${ARCHINIT_BRANCH}' from ${ARCHINIT_REPO}"
    echo "archinit: cloning to ${ARCHINIT_HOME}..."
    git clone --depth=1 --branch "${ARCHINIT_BRANCH}" "${ARCHINIT_REPO}" "${ARCHINIT_HOME}"
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

  # --- Seed personal configuration ---
  _seed_config

  # --- Run full install (skip with ARCHINIT_SKIP_INSTALL=1) ---
  if [[ -n ${ARCHINIT_SKIP_INSTALL:-} ]]; then
    printf '\n%s\n' "archinit: ARCHINIT_SKIP_INSTALL set — skipping install."
    printf '%s\n'   "archinit: Run 'archinit install --yes' when ready."
  else
    printf '\narchinit: Starting full install...\n\n'
    "${ARCHINIT_HOME}/bin/archinit" install --yes
  fi

  printf '\n%s\n' "archinit: Bootstrap complete!"
  printf '%s\n'   "archinit: Reload your shell or run: source ~/.zshrc"
}

main "$@"
