#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

log_info() { printf '[INFO] %s\n' "$*"; }
log_ok() { printf '[ OK ] %s\n' "$*"; }
log_warn() { printf '[WARN] %s\n' "$*"; }
log_error() { printf '[ERR ] %s\n' "$*"; }

die() {
	log_error "$*"
	exit 1
}

require_cmd() {
	local cmd="${1:?command required}"
	command -v "$cmd" >/dev/null 2>&1 || die "required command not found: ${cmd}"
}

is_arch() {
	[[ -f /etc/arch-release ]]
}

as_root() {
	if [[ ${EUID} -eq 0 ]]; then
		"$@"
	else
		sudo "$@"
	fi
}

detect_target_user() {
	if [[ -n ${SUDO_USER:-} && ${SUDO_USER} != "root" ]]; then
		printf '%s\n' "$SUDO_USER"
		return 0
	fi

	if [[ -n ${USER:-} ]]; then
		printf '%s\n' "$USER"
		return 0
	fi

	die "unable to detect target user"
}

current_login_shell() {
	local user="${1:?user required}"
	getent passwd "$user" | awk -F: '{print $7}'
}

ensure_zsh_installed() {
	if command -v zsh >/dev/null 2>&1; then
		log_ok "zsh is already installed"
		return 0
	fi

	log_info "Installing zsh"
	as_root pacman -S --needed --noconfirm zsh
	log_ok "zsh installed"
}

ensure_shell_in_etc_shells() {
	local zsh_path="${1:?zsh path required}"

	if grep -qxF "$zsh_path" /etc/shells; then
		return 0
	fi

	log_warn "${zsh_path} missing from /etc/shells; adding it"
	as_root sh -c "printf '%s\\n' '$zsh_path' >> /etc/shells"
}

ensure_default_shell() {
	local user="${1:?user required}"
	local zsh_path="${2:?zsh path required}"
	local current_shell

	current_shell="$(current_login_shell "$user")"
	[[ -n $current_shell ]] || die "could not read current shell for user: ${user}"

	if [[ "$current_shell" == "$zsh_path" ]]; then
		log_ok "default shell for ${user} is already ${zsh_path}"
		return 0
	fi

	log_info "Changing default shell for ${user} from ${current_shell} to ${zsh_path}"

	if [[ ${EUID} -eq 0 ]]; then
		chsh -s "$zsh_path" "$user"
	elif [[ "$user" == "$USER" ]]; then
		chsh -s "$zsh_path"
	else
		as_root chsh -s "$zsh_path" "$user"
	fi

	current_shell="$(current_login_shell "$user")"
	if [[ "$current_shell" == "$zsh_path" ]]; then
		log_ok "default shell updated to ${zsh_path} for ${user}"
		return 0
	fi

	die "failed to change default shell for ${user}"
}

main() {
	local target_user zsh_path

	require_cmd awk
	require_cmd getent
	require_cmd grep
	require_cmd pacman

	is_arch || die "This script supports Arch Linux only"

	if [[ ${EUID} -ne 0 ]]; then
		require_cmd sudo
		sudo -v || die "sudo access is required"
	fi

	target_user="$(detect_target_user)"
	ensure_zsh_installed

	zsh_path="$(command -v zsh)"
	[[ -n $zsh_path ]] || die "zsh binary not found after installation"

	ensure_shell_in_etc_shells "$zsh_path"
	ensure_default_shell "$target_user" "$zsh_path"

	log_ok "zsh is installed and set as default shell for ${target_user}"
}

main "$@"
