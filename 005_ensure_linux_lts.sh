#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

ASSUME_YES=false
NO_REBOOT=false
SKIP_BOOTLOADER=false
DRY_RUN=false

CHANGED_PACKAGES=false
CHANGED_BOOTLOADER=false
CHANGED_PRESET=false

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
Usage: 005_ensure_linux_lts.sh [options]

Ensure linux-lts is installed and configured as the default boot target when
supported bootloader files are detected. On systemd-boot/UKI setups, also
diagnoses and fixes /etc/mkinitcpio.d/linux-lts.preset when it is missing or
not configured to build a Unified Kernel Image, mirroring whatever the
mainline linux.preset already does.

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

# Run read-only commands with the same privileges as changes. Unlike as_root,
# this is intentionally not suppressed by --dry-run so checks still report the
# machine's actual configuration.
as_root_readonly() {
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

# is_running_in_container — return 0 if running inside a container/chroot.
# Containers never boot a kernel directly: kernel packages typically don't
# get a real /boot/vmlinuz-* extracted and no bootloader is ever installed,
# so the kernel-artifact and bootloader checks below would otherwise raise
# false-alarm warnings for something this script has no business "fixing".
is_running_in_container() {
  [[ -f /run/.containerenv || -f /.dockerenv ]] && return 0
  if command -v systemd-detect-virt >/dev/null 2>&1; then
    systemd-detect-virt --container --quiet && return 0
  fi
  return 1
}

mkinitcpio_preset_file() {
  printf '%s\n' "/etc/mkinitcpio.d/linux-lts.preset"
}

mainline_preset_file() {
  printf '%s\n' "/etc/mkinitcpio.d/linux.preset"
}

# preset_get_value PRESET_FILE VAR — print the value assigned to an
# uncommented `VAR=` line in a mkinitcpio preset (quotes stripped), or
# nothing if VAR is not set. Same lightweight text parse as
# preset_default_uki_path, generalized to arbitrary preset variables.
preset_get_value() {
  local preset_file="${1:?preset file required}"
  local var="${2:?variable name required}"
  local line val

  [[ -f $preset_file ]] || return 1

  line="$(grep -E "^${var}=" "$preset_file" || true)"
  [[ -n $line ]] || return 1

  val="${line#"${var}"=}"
  val="${val%%#*}"
  val="${val%\"}"
  val="${val#\"}"
  val="${val%\'}"
  val="${val#\'}"
  printf '%s\n' "$val"
}

# derive_lts_uki_path MAINLINE_UKI_PATH — turn a mainline UKI path (e.g.
# /boot/EFI/Linux/arch-linux.efi) into the analogous linux-lts path
# (/boot/EFI/Linux/arch-linux-lts.efi) by inserting a '-lts' suffix before
# the .efi extension, preserving directory and naming scheme.
derive_lts_uki_path() {
  local path="${1:?uki path required}"
  local dir base

  dir="$(dirname "$path")"
  base="$(basename "$path")"

  if [[ $base == *.efi ]]; then
    printf '%s/%s-lts.efi\n' "$dir" "${base%.efi}"
  else
    printf '%s/%s-lts\n' "$dir" "$base"
  fi
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

# ensure_lts_preset — diagnose and, if necessary, fix
# /etc/mkinitcpio.d/linux-lts.preset so it builds a Unified Kernel Image.
#
# Root cause this addresses: pacman ships linux-lts.preset with the
# traditional default_image= layout. If the mainline kernel's preset was
# hand-edited for UKI (per the Arch wiki systemd-boot UKI setup) *after*
# that, linux-lts never gets the same treatment — it either predates the
# switch to UKI or was freshly (re)installed from the package's template.
# Either way mkinitcpio has nothing telling it to emit an .efi for -lts, so
# no /boot/EFI/Linux/arch-linux-lts.efi is ever produced. This mirrors
# whatever default_uki/options the mainline preset already uses.
ensure_lts_preset() {
  local mainline_preset lts_preset
  local mainline_uki mainline_default_options mainline_fallback_uki mainline_fallback_options
  local lts_uki lts_fallback_uki current_uki
  local tmp

  if is_running_in_container; then
    log_info "Running in a container/chroot; skipping linux-lts.preset UKI configuration"
    return 0
  fi

  mainline_preset="$(mainline_preset_file)"
  lts_preset="$(mkinitcpio_preset_file)"

  if [[ ! -f $mainline_preset ]]; then
    log_warn "Mainline preset not found (${mainline_preset}); cannot derive UKI settings for linux-lts"
    return 1
  fi

  mainline_uki="$(preset_default_uki_path "$mainline_preset")"
  if [[ -z $mainline_uki ]]; then
    log_info "Mainline kernel is not configured for UKI (no default_uki in ${mainline_preset}); nothing to mirror for linux-lts"
    return 0
  fi
  log_info "Mainline UKI setup detected: default_uki=${mainline_uki} (${mainline_preset})"

  lts_uki="$(derive_lts_uki_path "$mainline_uki")"
  mainline_default_options="$(preset_get_value "$mainline_preset" default_options || true)"
  mainline_fallback_uki="$(preset_get_value "$mainline_preset" fallback_uki || true)"
  mainline_fallback_options="$(preset_get_value "$mainline_preset" fallback_options || true)"
  lts_fallback_uki=""
  [[ -n $mainline_fallback_uki ]] && lts_fallback_uki="$(derive_lts_uki_path "$mainline_fallback_uki")"

  if [[ -f $lts_preset ]]; then
    current_uki="$(preset_default_uki_path "$lts_preset")"
    if [[ $current_uki == "$lts_uki" ]]; then
      log_ok "linux-lts.preset already configured for UKI (default_uki=${lts_uki})"
      return 0
    fi
    if [[ -n $current_uki ]]; then
      log_warn "linux-lts.preset declares default_uki=${current_uki}, expected ${lts_uki}; rewriting"
    else
      log_warn "linux-lts.preset exists but is not configured for UKI (uses default_image=); rewriting to match mainline's UKI setup"
    fi
  else
    log_warn "linux-lts.preset not found (${lts_preset}); creating it"
  fi

  tmp="$(mktemp)"
  trap 'rm -f "$tmp"; trap - RETURN' RETURN
  {
    printf '# mkinitcpio preset file for the '\''linux-lts'\'' package (generated by 005_ensure_linux_lts.sh)\n\n'
    printf 'ALL_kver="/boot/vmlinuz-linux-lts"\n'
    grep -E '^ALL_microcode=' "$mainline_preset" 2>/dev/null || true
    printf '\n'
    if [[ -n $lts_fallback_uki ]]; then
      printf "PRESETS=('default' 'fallback')\n\n"
    else
      printf "PRESETS=('default')\n\n"
    fi
    printf 'default_uki="%s"\n' "$lts_uki"
    [[ -n $mainline_default_options ]] && printf 'default_options="%s"\n' "$mainline_default_options"
    if [[ -n $lts_fallback_uki ]]; then
      printf '\n'
      printf 'fallback_uki="%s"\n' "$lts_fallback_uki"
      [[ -n $mainline_fallback_options ]] && printf 'fallback_options="%s"\n' "$mainline_fallback_options"
    fi
  } >"$tmp"

  if $DRY_RUN; then
    log_info "[dry-run] Would write ${lts_preset}:"
    sed 's/^/[dry-run]   /' "$tmp"
    return 0
  fi

  set_root_owned_file "$lts_preset" "$tmp"
  CHANGED_PRESET=true
  log_ok "linux-lts.preset written with default_uki=${lts_uki}"

  # Quick verification: re-read the file back off disk to confirm the write
  # landed and mkinitcpio will see an uncommented default_uki= line.
  if preset_get_value "$lts_preset" default_uki >/dev/null 2>&1; then
    log_ok "Verified: ${lts_preset} now declares default_uki=$(preset_get_value "$lts_preset" default_uki)"
  else
    log_error "Verification failed: ${lts_preset} still missing default_uki after write"
    return 1
  fi
}

# verify_lts_kernel_artifact — confirm mkinitcpio actually produced a bootable
# linux-lts image, whether that's a classic vmlinuz+initramfs pair or a UKI.
# Diagnostic only: building is handled by rebuild_initramfs_if_needed / the
# pacman kernel-install hook, this just reports whether it worked.
verify_lts_kernel_artifact() {
  local preset_file uki_path uki_file

  if is_running_in_container; then
    log_info "Running in a container/chroot; skipping kernel artifact verification (no real boot partition expected)"
    return 0
  fi

  preset_file="$(mkinitcpio_preset_file)"
  if [[ ! -f $preset_file ]]; then
    log_warn "mkinitcpio preset not found: ${preset_file} (linux-lts install may be incomplete)"
    return 1
  fi

  uki_path="$(preset_default_uki_path "$preset_file")"

  if [[ -n $uki_path ]]; then
    if [[ -f $uki_path ]]; then
      log_ok "linux-lts UKI present: ${uki_path}"
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
  else
    tmp="$(mktemp)"
    trap 'rm -f "$tmp"; trap - RETURN' RETURN
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
    log_ok "systemd-boot default set to ${entry} in ${loader_conf}"
  fi

  if command -v bootctl >/dev/null 2>&1; then
    if ! as_root bootctl set-default "$entry"; then
      log_warn "failed to set systemd-boot EFI default to ${entry} with bootctl"
      return 1
    fi
    CHANGED_BOOTLOADER=true
    log_ok "systemd-boot EFI default set to ${entry}"
  fi
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
  trap 'rm -f "$tmp"; trap - RETURN' RETURN
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

# bootctl_confirms_systemd_boot — determine the active bootloader from
# bootctl's status output instead of inferring it solely from directories on
# the ESP. `bootctl list` can inspect BLS entries even when a different
# bootloader is active, so status is the controlling check before changing
# loader.conf.
bootctl_confirms_systemd_boot() {
  local bootctl_status

  command -v bootctl >/dev/null 2>&1 || return 1
  bootctl_status="$(as_root_readonly bootctl --no-pager status 2>/dev/null)" || return 1
  grep -Eq '^[[:space:]]*Product:[[:space:]]+systemd-boot([[:space:]]|$)' <<<"$bootctl_status"
}

# verify_systemd_boot_lts_default ENTRY — confirm `bootctl list` reports the
# exact desired entry as a Type #2 UKI and marks it as the default. Checking
# only for a filename would miss a system such as one where arch-linux-lts.efi
# exists but arch-linux.efi remains selected.
verify_systemd_boot_lts_default() {
  local entry="${1:?entry required}"
  local bootctl_list

  if ! bootctl_list="$(as_root_readonly bootctl --no-pager list 2>/dev/null)"; then
    log_warn "Could not read boot entries with 'bootctl --no-pager list'"
    return 1
  fi

  if awk -v expected="$entry" '
    function matches() {
      return type_uki && id == expected && is_default
    }
    /^[[:space:]]*$/ {
      if (matches()) {
        found = 1
        exit
      }
      type_uki = id = is_default = 0
      next
    }
    /^[[:space:]]*type:[[:space:]]+Boot Loader Specification Type #2/ {
      type_uki = 1
      next
    }
    /^[[:space:]]*title:/ && /\(default\)/ {
      is_default = 1
      next
    }
    /^[[:space:]]*id:[[:space:]]*/ {
      sub(/^[[:space:]]*id:[[:space:]]*/, "")
      id = $0
    }
    END {
      if (matches()) {
        found = 1
      }
      exit !found
    }
  ' <<<"$bootctl_list"; then
    log_ok "systemd-boot confirms ${entry} is the default Type #2 UKI"
    return 0
  fi

  log_warn "bootctl did not report ${entry} as the default Type #2 UKI; inspect 'sudo bootctl --no-pager list' and /boot/loader/loader.conf"
  return 1
}

configure_systemd_boot_default() {
  local entry uki_path uki_file

  if entry="$(find_systemd_boot_lts_entry)"; then
    set_systemd_boot_default "$entry"
    verify_systemd_boot_lts_default "$entry"
    return
  fi

  # No classic loader entry — linux-lts may be built as a Unified Kernel
  # Image instead. UKIs dropped into /EFI/Linux are auto-discovered by
  # systemd-boot as Type #2 entries whose id is just the file's basename, so
  # the same loader.conf `default` mechanism applies.
  uki_path="$(preset_default_uki_path "$(mkinitcpio_preset_file)")"
  if uki_file="$(find_uki_lts_file "$uki_path")"; then
    log_info "systemd-boot: linux-lts is a UKI, using $(basename "$uki_file") as the boot entry"
    entry="$(basename "$uki_file")"
    set_systemd_boot_default "$entry"
    verify_systemd_boot_lts_default "$entry"
    return
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

  if is_running_in_container; then
    log_info "Running in a container/chroot; skipping bootloader alignment (no bootloader expected)"
    return 0
  fi

  if bootctl_confirms_systemd_boot; then
    found=true
    if configure_systemd_boot_default; then
      ok=true
    fi
  elif command -v bootctl >/dev/null 2>&1; then
    log_warn "bootctl is available but did not confirm systemd-boot; skipping systemd-boot configuration"
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
  local preset_file uki_path artifact_missing=false

  preset_file="$(mkinitcpio_preset_file)"
  uki_path="$(preset_default_uki_path "$preset_file")"
  if [[ -n $uki_path ]] && [[ ! -f $uki_path ]]; then
    artifact_missing=true
  fi

  if ! $CHANGED_PACKAGES && ! $CHANGED_PRESET && ! $artifact_missing; then
    log_info "Skipping initramfs rebuild (no package/preset changes and linux-lts artifact already present)"
    return 0
  fi

  log_info "Rebuilding initramfs/UKIs for all presets (mkinitcpio -P)"
  as_root mkinitcpio -P
  log_ok "Initramfs/UKI rebuild finished"

  # Quick verification: confirm the rebuild actually produced the linux-lts
  # UKI this run was meant to fix, instead of silently trusting exit code 0.
  if $DRY_RUN; then
    log_info "[dry-run] Skipping post-rebuild artifact verification"
    return 0
  fi

  if [[ -n $uki_path ]]; then
    if [[ -f $uki_path ]]; then
      log_ok "Verified: ${uki_path} exists after rebuild"
    else
      log_error "Verification failed: expected UKI ${uki_path} still missing after rebuild; check 'sudo mkinitcpio -p linux-lts' output for errors"
      return 1
    fi
  fi
}

print_final_status() {
  local artifact_status="${1:-0}"
  local bootloader_status="${2:-0}"

  if running_kernel_is_lts; then
    log_ok "Running kernel is already linux-lts"
  else
    log_warn "Running kernel is not linux-lts yet (reboot required)"
  fi

  if $CHANGED_PACKAGES || $CHANGED_BOOTLOADER || $CHANGED_PRESET; then
    if $DRY_RUN; then
      log_warn "[dry-run] Changes would be applied. Reboot would be required to start linux-lts"
    else
      log_warn "Changes were applied. Reboot to start linux-lts: sudo reboot"
    fi
    return
  fi

  if [[ $artifact_status -ne 0 || $bootloader_status -ne 0 ]]; then
    log_warn "No changes were made, but verification above reported problems; system may not be fully compliant"
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
  require_cmd dirname
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
  ensure_lts_preset || artifact_status=1
  rebuild_initramfs_if_needed || artifact_status=1

  verify_lts_kernel_artifact || artifact_status=1

  if ! $SKIP_BOOTLOADER; then
    if ! configure_bootloader_defaults; then
      bootloader_status=1
    fi
  else
    log_info "Skipping bootloader default alignment by request"
  fi

  print_final_status "$artifact_status" "$bootloader_status"

  if [[ $bootloader_status -ne 0 || $artifact_status -ne 0 ]]; then
    log_warn "Completed with warnings; review messages above"
  fi

  if ! $NO_REBOOT && ! $ASSUME_YES && [[ -t 0 ]] && [[ -t 1 ]]; then
    log_info "Reboot is not automatic. Run: sudo reboot"
  fi

  return 0
}

main "$@"