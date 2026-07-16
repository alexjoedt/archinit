#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

ASSUME_YES=false
NO_REBOOT=false
SKIP_BOOTLOADER=false
DRY_RUN=false

CHANGED_PACKAGES=false
CHANGED_BOOTLOADER=false

log_info() { printf '[INFO] %s\n' "$*"; }
log_ok() { printf '[ OK ] %s\n' "$*"; }
log_warn() { printf '[WARN] %s\n' "$*"; }
log_error() { printf '[ERR ] %s\n' "$*"; }

die() {
  log_error "$*"
  exit 1
}

usage() {
  cat <<'EOF'
Usage: ensure_linux_lts.sh [options]

Ensure linux-lts is installed and configured as the default boot target when
supported bootloader files are detected.

Options:
  --yes              Fully non-interactive automation; also suppresses the
                     final reboot hint (this script never prompts for
                     confirmation, --yes only affects that hint)
  --no-reboot        Suppress the final reboot hint (prints guidance only)
  --skip-bootloader  Do not modify bootloader defaults
  --dry-run          Print changes without applying them
  -h, --help         Show this help message
EOF
}

require_cmd() {
  local cmd="${1:?command required}"
  command -v "$cmd" >/dev/null 2>&1 || die "required command not found: ${cmd}"
}

is_arch() {
  [[ -f /etc/arch-release ]]
}

as_root() {
  if $DRY_RUN; then
    log_info "[dry-run] $*"
    return 0
  fi

  if [[ ${EUID} -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

set_root_owned_file() {
  local destination="${1:?destination required}"
  local source="${2:?source file required}"
  as_root install -Dm644 "$source" "$destination"
}

is_pkg_installed() {
  local pkg="${1:?package required}"
  pacman -Qi "$pkg" >/dev/null 2>&1
}

running_kernel_is_lts() {
  [[ "$(uname -r)" == *-lts* ]]
}

mkinitcpio_preset_file() {
  printf '%s\n' "/etc/mkinitcpio.d/linux-lts.preset"
}

# preset_default_uki_path PRESET_FILE — print the path configured via
# `default_uki=` in a mkinitcpio preset, or nothing if the preset is missing
# or uses the traditional vmlinuz+initramfs layout (`default_image=`)
# instead. Presence of an uncommented `default_uki=` line is what
# distinguishes a Unified Kernel Image (UKI) build from a classic one.
preset_default_uki_path() {
  local preset_file="${1:?preset file required}"
  local line path

  [[ -f $preset_file ]] || return 0

  line="$(grep -E '^default_uki=' "$preset_file" || true)"
  [[ -n $line ]] || return 0

  path="${line#default_uki=}"
  path="${path%%#*}"
  path="${path%\"}"
  path="${path#\"}"
  path="${path%\'}"
  path="${path#\'}"
  printf '%s\n' "$path"
}

# find_uki_lts_file [DECLARED_PATH] — resolve the on-disk UKI file for
# linux-lts. Prefers DECLARED_PATH (taken from the preset) if it exists;
# preset files are shell-sourced by mkinitcpio and may reference variables a
# plain text parse cannot resolve, so this falls back to scanning the ESP's
# /EFI/Linux directory for a plausibly named *.efi file.
find_uki_lts_file() {
  local declared="${1:-}"
  local esp_dir="/boot/EFI/Linux"
  local file base

  if [[ -n $declared && -f $declared ]]; then
    printf '%s\n' "$declared"
    return 0
  fi

  [[ -d $esp_dir ]] || return 1

  for file in "$esp_dir"/*.efi; do
    [[ -f $file ]] || continue
    base="$(basename "$file")"
    if [[ ${base,,} == *lts* ]]; then
      printf '%s\n' "$file"
      return 0
    fi
  done

  return 1
}

# verify_lts_kernel_artifact — confirm mkinitcpio actually produced a bootable
# linux-lts image, whether that's a classic vmlinuz+initramfs pair or a UKI.
# Diagnostic only: building is handled by rebuild_initramfs_if_needed / the
# pacman kernel-install hook, this just reports whether it worked.
verify_lts_kernel_artifact() {
  local preset_file uki_path uki_file

  preset_file="$(mkinitcpio_preset_file)"
  if [[ ! -f $preset_file ]]; then
    log_warn "mkinitcpio preset not found: ${preset_file} (linux-lts install may be incomplete)"
    return 1
  fi

  uki_path="$(preset_default_uki_path "$preset_file")"

  if [[ -n $uki_path ]]; then
    if uki_file="$(find_uki_lts_file "$uki_path")"; then
      log_ok "linux-lts UKI present: ${uki_file}"
      return 0
    fi
    log_warn "linux-lts.preset declares a UKI (${uki_path}) but it was not found; check 'sudo mkinitcpio -p linux-lts' output for errors"
    return 1
  fi

  if [[ ! -f /boot/vmlinuz-linux-lts ]]; then
    log_warn "linux-lts kernel image not found at /boot/vmlinuz-linux-lts"
    return 1
  fi
  if [[ ! -f /boot/initramfs-linux-lts.img ]]; then
    log_warn "linux-lts initramfs not found at /boot/initramfs-linux-lts.img"
    return 1
  fi

  log_ok "linux-lts kernel image and initramfs present"
  return 0
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --yes)
        ASSUME_YES=true
        ;;
      --no-reboot)
        NO_REBOOT=true
        ;;
      --skip-bootloader)
        SKIP_BOOTLOADER=true
        ;;
      --dry-run)
        DRY_RUN=true
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        usage
        die "unknown option: $1"
        ;;
    esac
    shift
  done
}

ensure_packages() {
  local -a needed=()

  if ! is_pkg_installed linux-lts; then
    needed+=(linux-lts)
  fi
  if ! is_pkg_installed linux-lts-headers; then
    needed+=(linux-lts-headers)
  fi

  if [[ ${#needed[@]} -eq 0 ]]; then
    log_ok "linux-lts and linux-lts-headers already installed"
    return 0
  fi

  log_info "Installing missing packages: ${needed[*]}"
  as_root pacman -S --needed --noconfirm -- "${needed[@]}"
  CHANGED_PACKAGES=true
  log_ok "Kernel packages ensured"
}

find_systemd_boot_lts_entry() {
  local entries_dir="/boot/loader/entries"
  local entry file

  [[ -d $entries_dir ]] || return 1

  for file in "$entries_dir"/*.conf; do
    [[ -f $file ]] || continue

    # The vmlinuz-linux-lts check is the reliable match. The title fallback
    # is intentionally loose (matches "lts" as a whole word anywhere in the
    # title) to catch hand-edited entries; it can theoretically false-positive
    # on an unrelated entry whose title happens to contain "lts".
    if grep -Eq '^\s*linux\s+.*vmlinuz-linux-lts(\s|$)' "$file" || \
      grep -Eqi '^\s*title\s+.*\blts\b' "$file"; then
      entry="$(basename "$file")"
      printf '%s\n' "$entry"
      return 0
    fi
  done

  return 1
}

loader_default_is() {
  local expected="${1:?expected entry required}"
  local loader_conf="/boot/loader/loader.conf"
  local current

  [[ -f $loader_conf ]] || return 1
  current="$(awk '/^default[[:space:]]+/ {print $2; exit}' "$loader_conf" 2>/dev/null || true)"
  [[ $current == "$expected" ]]
}

set_systemd_boot_default() {
  local entry="${1:?entry required}"
  local loader_conf="/boot/loader/loader.conf"
  local tmp

  if loader_default_is "$entry"; then
    log_ok "systemd-boot default already points to ${entry}"
    return 0
  fi

  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' RETURN
  if [[ -f $loader_conf ]]; then
    awk -v entry="$entry" '
      BEGIN { done = 0 }
      /^default[[:space:]]+/ {
        if (!done) {
          print "default " entry
          done = 1
        }
        next
      }
      { print }
      END {
        if (!done) {
          print "default " entry
        }
      }
    ' "$loader_conf" >"$tmp"
  else
    printf 'default %s\n' "$entry" >"$tmp"
  fi

  set_root_owned_file "$loader_conf" "$tmp"
  CHANGED_BOOTLOADER=true
  log_ok "systemd-boot default set to ${entry}"
}

detect_grub_cfg_path() {
  if [[ -f /boot/grub/grub.cfg ]]; then
    printf '%s\n' /boot/grub/grub.cfg
    return 0
  fi
  if [[ -f /boot/grub2/grub.cfg ]]; then
    printf '%s\n' /boot/grub2/grub.cfg
    return 0
  fi
  return 1
}

# find_grub_lts_title GRUB_CFG — print the title of the first top-level
# linux-lts menuentry, or nothing if none is found.
#
# NOTE: only scans top-level `menuentry` lines. If the linux-lts kernel is
# nested inside a `submenu` (grub-mkconfig commonly does this for "Advanced
# options"), grub-set-default needs a "submenu>entry" path and this simple
# title alone will not resolve correctly.
find_grub_lts_title() {
  local grub_cfg="${1:?grub cfg path required}"
  local title

  # The `|| true` is required: under `set -eo pipefail`, grep exiting 1 (no
  # match) would otherwise make this whole pipeline's status non-zero and
  # kill the script via errexit before the caller's empty-string check ever
  # runs.
  title="$(grep -m1 -E "^menuentry '.*linux-lts" "$grub_cfg" | sed -E "s/^menuentry '([^']+)'.*/\1/" || true)"
  printf '%s\n' "$title"
}

ensure_grub_default_saved_mode() {
  local defaults_file="/etc/default/grub"
  local tmp

  [[ -f $defaults_file ]] || return 1

  if grep -Eq '^GRUB_DEFAULT=saved$' "$defaults_file"; then
    printf '%s\n' nochange
    return 0
  fi

  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' RETURN
  awk '
    BEGIN { done = 0 }
    /^GRUB_DEFAULT=/ {
      if (!done) {
        print "GRUB_DEFAULT=saved"
        done = 1
      }
      next
    }
    { print }
    END {
      if (!done) {
        print "GRUB_DEFAULT=saved"
      }
    }
  ' "$defaults_file" >"$tmp"

  set_root_owned_file "$defaults_file" "$tmp"
  CHANGED_BOOTLOADER=true
  log_info "Set GRUB_DEFAULT=saved in ${defaults_file}"
  printf '%s\n' changed
  return 0
}

configure_systemd_boot_default() {
  local entry uki_path uki_file

  if entry="$(find_systemd_boot_lts_entry)"; then
    set_systemd_boot_default "$entry"
    return 0
  fi

  # No classic loader entry — linux-lts may be built as a Unified Kernel
  # Image instead. UKIs dropped into /EFI/Linux are auto-discovered by
  # systemd-boot as Type #2 entries whose id is just the file's basename, so
  # the same loader.conf `default` mechanism applies.
  uki_path="$(preset_default_uki_path "$(mkinitcpio_preset_file)")"
  if uki_file="$(find_uki_lts_file "$uki_path")"; then
    log_info "systemd-boot: linux-lts is a UKI, using $(basename "$uki_file") as the boot entry"
    set_systemd_boot_default "$(basename "$uki_file")"
    return 0
  fi

  log_warn "systemd-boot detected but no linux-lts entry found (checked classic loader entries and UKI)"
  return 1
}

configure_grub_default() {
  local grub_cfg lts_title saved_mode_state
  local changed_saved_mode=false

  grub_cfg="$(detect_grub_cfg_path)" || {
    log_warn "GRUB tooling detected but grub.cfg not found"
    return 1
  }

  lts_title="$(find_grub_lts_title "$grub_cfg")"
  if [[ -z $lts_title ]]; then
    local uki_path uki_file
    uki_path="$(preset_default_uki_path "$(mkinitcpio_preset_file)")"
    if uki_file="$(find_uki_lts_file "$uki_path")"; then
      log_warn "linux-lts is built as a Unified Kernel Image ($(basename "$uki_file")); GRUB does not auto-generate a menu entry for UKIs, configure GRUB manually if you need it as the default"
    else
      log_warn "GRUB config does not contain a linux-lts menu entry"
    fi
    return 1
  fi

  if saved_mode_state="$(ensure_grub_default_saved_mode)"; then
    if [[ $saved_mode_state == changed ]]; then
      changed_saved_mode=true
    fi
  fi

  if [[ ! -f /boot/grub/grubenv && ! -f /boot/grub2/grubenv ]]; then
    log_warn "grubenv was not found; skipping grub-set-default"
    return 1
  fi

  if as_root grub-set-default "$lts_title"; then
    CHANGED_BOOTLOADER=true
    log_ok "GRUB default set to: ${lts_title}"
  else
    log_warn "failed to run grub-set-default for linux-lts entry"
    return 1
  fi

  if $changed_saved_mode; then
    if ! as_root grub-mkconfig -o "$grub_cfg"; then
      log_warn "failed to regenerate GRUB config at ${grub_cfg}"
      return 1
    fi
    log_ok "Regenerated GRUB config at ${grub_cfg}"
  fi

  return 0
}

configure_bootloader_defaults() {
  local found=false
  local ok=false

  # /boot/loader/entries may not exist on a pure-UKI systemd-boot setup (no
  # classic Type #1 entries at all), so also treat loader.conf or a populated
  # ESP /EFI/Linux as evidence that systemd-boot is in use.
  if [[ -d /boot/loader/entries || -f /boot/loader/loader.conf || -d /boot/EFI/Linux ]]; then
    found=true
    if configure_systemd_boot_default; then
      ok=true
    fi
  fi

  if command -v grub-set-default >/dev/null 2>&1 || command -v grub-mkconfig >/dev/null 2>&1; then
    found=true
    if command -v grub-set-default >/dev/null 2>&1 && command -v grub-mkconfig >/dev/null 2>&1; then
      if configure_grub_default; then
        ok=true
      fi
    else
      log_warn "GRUB detected but required commands are missing (need grub-set-default and grub-mkconfig)"
    fi
  fi

  if ! $found; then
    log_info "No supported bootloader layout detected; skipping boot default alignment"
    return 0
  fi

  if ! $ok; then
    log_warn "Could not automatically confirm linux-lts as boot default"
    return 1
  fi

  return 0
}

rebuild_initramfs_if_needed() {
  if ! $CHANGED_PACKAGES; then
    log_info "Skipping initramfs rebuild (no kernel package changes)"
    return 0
  fi

  log_info "Rebuilding initramfs"
  as_root mkinitcpio -P
  log_ok "Initramfs rebuilt"
}

print_final_status() {
  if running_kernel_is_lts; then
    log_ok "Running kernel is already linux-lts"
  else
    log_warn "Running kernel is not linux-lts yet (reboot required)"
  fi

  if $CHANGED_PACKAGES || $CHANGED_BOOTLOADER; then
    if $DRY_RUN; then
      log_warn "[dry-run] Changes would be applied. Reboot would be required to start linux-lts"
    else
      log_warn "Changes were applied. Reboot to start linux-lts: sudo reboot"
    fi
    return
  fi

  log_ok "No changes needed; system already compliant"
}

main() {
  local bootloader_status=0
  local artifact_status=0

  parse_args "$@"

  require_cmd awk
  require_cmd basename
  require_cmd grep
  require_cmd install
  require_cmd mktemp
  require_cmd pacman
  require_cmd sed
  require_cmd uname
  require_cmd mkinitcpio

  is_arch || die "This script supports Arch Linux only"

  if [[ ${EUID} -ne 0 ]]; then
    require_cmd sudo
    sudo -v || die "sudo access is required"
  fi

  ensure_packages
  rebuild_initramfs_if_needed

  verify_lts_kernel_artifact || artifact_status=1

  if ! $SKIP_BOOTLOADER; then
    if ! configure_bootloader_defaults; then
      bootloader_status=1
    fi
  else
    log_info "Skipping bootloader default alignment by request"
  fi

  print_final_status

  if [[ $bootloader_status -ne 0 || $artifact_status -ne 0 ]]; then
    log_warn "Completed with warnings; review messages above"
  fi

  if ! $NO_REBOOT && ! $ASSUME_YES && [[ -t 0 ]] && [[ -t 1 ]]; then
    log_info "Reboot is not automatic. Run: sudo reboot"
  fi

  return 0
}

main "$@"