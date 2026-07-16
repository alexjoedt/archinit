#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

DRY_RUN=false
SWAPFILE="/swapfile"
CMDLINE_FILE="/etc/kernel/cmdline"
MKINITCPIO_CONF="/etc/mkinitcpio.conf"
FSTAB_FILE="/etc/fstab"
BUFFER_PERCENT=10

CHANGED_CMDLINE=false
CHANGED_MKINITCPIO=false

ROOT_FSTYPE=""
ROOT_UUID=""
RESUME_OFFSET=""
REQUIRED_BYTES=0

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
Usage: setup_hibernate_swap.sh [options]

Create /swapfile for hibernation at installed RAM plus a 10% buffer, add it to
/etc/fstab, configure resume=UUID=... resume_offset=... in /etc/kernel/cmdline,
enable mkinitcpio's resume hook, and rebuild initramfs/UKI artifacts.

The script refuses to modify systems with any existing active swap and supports
Btrfs, ext4, and XFS root filesystems only.

Options:
  --dry-run  Print changes without applying them
  -h, --help Show this help text
EOF
}

require_cmd() {
  local cmd="${1:?command required}"
  command -v "$cmd" >/dev/null 2>&1 || die "required command not found: ${cmd}"
}

is_arch() {
  [[ -f /etc/arch-release ]]
}

is_running_in_container() {
  [[ -f /run/.containerenv || -f /.dockerenv ]] && return 0
  if command -v systemd-detect-virt >/dev/null 2>&1; then
    systemd-detect-virt --container --quiet && return 0
  fi
  return 1
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

as_root_readonly() {
  if [[ ${EUID} -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

set_root_owned_file() {
  local destination="${1:?destination required}"
  local source="${2:?source required}"

  as_root install -Dm644 "$source" "$destination"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
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

memory_kib() {
  awk '/^MemTotal:/ { print $2; exit }' /proc/meminfo
}

format_kib() {
  local kib="${1:?KiB required}"
  awk -v kib="$kib" 'BEGIN {
    if (kib >= 1048576) printf "%.2f GiB", kib / 1048576
    else printf "%.2f MiB", kib / 1024
  }'
}

check_existing_swap() {
  local active_swap

  active_swap="$(as_root_readonly swapon --noheadings --show=NAME)"
  [[ -z $active_swap ]] || die "active swap already exists (${active_swap//$'\n'/, }); refusing to modify swap configuration"

  [[ ! -e $SWAPFILE ]] || die "${SWAPFILE} already exists; inspect or remove it before running this script"

  if awk -v swapfile="$SWAPFILE" '$1 == swapfile && $3 == "swap" { found = 1 } END { exit !found }' "$FSTAB_FILE"; then
    die "${FSTAB_FILE} already contains a ${SWAPFILE} swap entry; inspect it before running this script"
  fi
}

detect_root_filesystem() {
  ROOT_FSTYPE="$(findmnt -n -o FSTYPE /)"
  ROOT_UUID="$(findmnt -n -o UUID /)"

  [[ -n $ROOT_UUID ]] || die "could not determine the UUID of the filesystem mounted at /"

  case "$ROOT_FSTYPE" in
    btrfs|ext4|xfs)
      ;;
    *)
      die "unsupported root filesystem for a hibernate swapfile: ${ROOT_FSTYPE:-unknown}"
      ;;
  esac
}

calculate_swap_size() {
  local ram_kib requested_kib page_size

  ram_kib="$(memory_kib)"
  [[ $ram_kib =~ ^[0-9]+$ ]] && [[ $ram_kib -gt 0 ]] || die "could not determine installed RAM from /proc/meminfo"

  requested_kib=$(((ram_kib * (100 + BUFFER_PERCENT) + 99) / 100))
  page_size="$(getconf PAGESIZE)"
  REQUIRED_BYTES=$(((requested_kib * 1024 + page_size - 1) / page_size * page_size))

  log_info "Installed RAM: $(format_kib "$ram_kib")"
  log_info "Hibernate buffer: ${BUFFER_PERCENT}%"
  log_info "Required swapfile size: $(format_kib "$((REQUIRED_BYTES / 1024))")"
}

check_available_space() {
  local available_kib required_kib safety_kib=$((1024 * 1024))

  available_kib="$(df -Pk / | awk 'NR == 2 { print $4 }')"
  required_kib=$((REQUIRED_BYTES / 1024))
  [[ $available_kib =~ ^[0-9]+$ ]] || die "could not determine available space on /"

  ((available_kib >= required_kib + safety_kib)) || die "insufficient free space on /: need $(format_kib "$((required_kib + safety_kib))") including a 1 GiB safety margin"
}

preflight() {
  is_arch || die "this script supports Arch Linux only"
  is_running_in_container && die "refusing to configure hibernation in a container or chroot"

  require_cmd awk
  require_cmd df
  require_cmd findmnt
  require_cmd getconf
  require_cmd grep
  require_cmd install
  require_cmd mkinitcpio
  require_cmd swapon

  [[ -f $CMDLINE_FILE ]] || die "kernel command line file not found: ${CMDLINE_FILE}"
  [[ -f $MKINITCPIO_CONF ]] || die "mkinitcpio configuration not found: ${MKINITCPIO_CONF}"
  [[ -f $FSTAB_FILE ]] || die "fstab not found: ${FSTAB_FILE}"

  if [[ ${EUID} -ne 0 ]]; then
    require_cmd sudo
    sudo -v || die "sudo access is required"
  fi

  check_existing_swap
  detect_root_filesystem

  case "$ROOT_FSTYPE" in
    btrfs)
      require_cmd btrfs
      ;;
    ext4|xfs)
      require_cmd fallocate
      require_cmd filefrag
      require_cmd mkswap
      require_cmd stat
      ;;
  esac

  calculate_swap_size
  check_available_space
}

create_btrfs_swapfile() {
  as_root btrfs filesystem mkswapfile --size "$REQUIRED_BYTES" "$SWAPFILE"
  RESUME_OFFSET="$(as_root_readonly btrfs inspect-internal map-swapfile -r "$SWAPFILE")"
  [[ $RESUME_OFFSET =~ ^[0-9]+$ ]] || die "could not determine Btrfs resume offset for ${SWAPFILE}"
}

create_extent_swapfile() {
  local page_size filesystem_block_size filefrag_output extent_count physical_block physical_bytes

  page_size="$(getconf PAGESIZE)"
  as_root fallocate -l "$REQUIRED_BYTES" "$SWAPFILE"
  as_root chmod 600 "$SWAPFILE"

  filesystem_block_size="$(as_root_readonly stat -f --format=%S "$SWAPFILE")"
  [[ $filesystem_block_size =~ ^[0-9]+$ ]] && [[ $filesystem_block_size -gt 0 ]] || die "could not determine filesystem block size for ${SWAPFILE}"

  filefrag_output="$(as_root_readonly filefrag -v "$SWAPFILE")"
  extent_count="$(awk '$1 ~ /^[0-9]+:$/ { count++ } END { print count + 0 }' <<<"$filefrag_output")"
  [[ $extent_count -eq 1 ]] || die "${SWAPFILE} is fragmented (${extent_count} extents); refusing to configure an unreliable resume offset"

  physical_block="$(awk '
    $1 ~ /^[0-9]+:$/ {
      physical = $4
      sub(/\.\..*/, "", physical)
      if (physical ~ /^[0-9]+$/) print physical
      exit
    }
  ' <<<"$filefrag_output")"
  [[ $physical_block =~ ^[0-9]+$ ]] || die "could not determine physical resume offset for ${SWAPFILE}"

  physical_bytes=$((physical_block * filesystem_block_size))
  ((physical_bytes % page_size == 0)) || die "physical swapfile offset is not aligned to the kernel page size"
  RESUME_OFFSET=$((physical_bytes / page_size))

  as_root mkswap "$SWAPFILE"
}

create_swapfile() {
  log_info "Creating ${SWAPFILE} on ${ROOT_FSTYPE}"

  if $DRY_RUN; then
    log_info "[dry-run] Physical resume offset will be calculated after ${SWAPFILE} is created"
    return 0
  fi

  case "$ROOT_FSTYPE" in
    btrfs)
      create_btrfs_swapfile
      ;;
    ext4|xfs)
      create_extent_swapfile
      ;;
  esac

  as_root swapon "$SWAPFILE"
  log_ok "Enabled ${SWAPFILE}; resume offset is ${RESUME_OFFSET}"
}

add_fstab_entry() {
  local temporary

  temporary="$(mktemp)"
  as_root_readonly cat "$FSTAB_FILE" >"$temporary"
  printf '\n%s none swap defaults 0 0\n' "$SWAPFILE" >>"$temporary"
  set_root_owned_file "$FSTAB_FILE" "$temporary"
  rm -f "$temporary"
  log_ok "Added ${SWAPFILE} to ${FSTAB_FILE}"
}

update_kernel_cmdline() {
  local current updated temporary

  current="$(as_root_readonly tr '\n' ' ' <"$CMDLINE_FILE")"
  current="$(awk '
    {
      for (index = 1; index <= NF; index++) {
        if ($index !~ /^resume=/ && $index !~ /^resume_offset=/) {
          printf "%s%s", separator, $index
          separator = " "
        }
      }
    }
  ' <<<"$current")"

  if $DRY_RUN && [[ -z $RESUME_OFFSET ]]; then
    log_info "[dry-run] Would update ${CMDLINE_FILE} after calculating the physical resume offset"
    return 0
  fi

  updated="${updated} resume=UUID=${ROOT_UUID} resume_offset=${RESUME_OFFSET}"

  if [[ $current == "$updated" ]]; then
    log_ok "${CMDLINE_FILE} already contains the current resume parameters"
    return 0
  fi

  temporary="$(mktemp)"
  printf '%s\n' "$updated" >"$temporary"
  set_root_owned_file "$CMDLINE_FILE" "$temporary"
  rm -f "$temporary"
  CHANGED_CMDLINE=true
  log_ok "Updated resume parameters in ${CMDLINE_FILE}"
}

ensure_resume_hook() {
  local hooks_line hooks_body replacement temporary
  local -a hooks hooks_lines updated_hooks
  local hook

  mapfile -t hooks_lines < <(grep -E '^[[:space:]]*HOOKS=\([^)]*\)[[:space:]]*(#.*)?$' "$MKINITCPIO_CONF" || true)
  [[ ${#hooks_lines[@]} -eq 1 ]] || die "could not safely parse exactly one single-line HOOKS=() declaration in ${MKINITCPIO_CONF}"
  hooks_line="${hooks_lines[0]}"
  hooks_body="${hooks_line#*(}"
  hooks_body="${hooks_body%%)*}"
  read -r -a hooks <<<"$hooks_body"

  for hook in "${hooks[@]}"; do
    [[ $hook == resume ]] && {
      log_ok "mkinitcpio resume hook already configured"
      return 0
    }
  done

  for hook in "${hooks[@]}"; do
    if [[ $hook == filesystems ]]; then
      updated_hooks+=(resume)
    fi
    updated_hooks+=("$hook")
  done
  [[ " ${updated_hooks[*]} " == *" resume "* ]] || die "mkinitcpio HOOKS does not contain filesystems; refusing to choose a resume hook position"

  replacement="HOOKS=(${updated_hooks[*]})"
  temporary="$(mktemp)"
  awk -v replacement="$replacement" '
    /^[[:space:]]*HOOKS=\(/ && !replaced { print replacement; replaced = 1; next }
    { print }
    END { exit !replaced }
  ' "$MKINITCPIO_CONF" >"$temporary"
  set_root_owned_file "$MKINITCPIO_CONF" "$temporary"
  rm -f "$temporary"
  CHANGED_MKINITCPIO=true
  log_ok "Added resume hook to ${MKINITCPIO_CONF}"
}

rebuild_initramfs() {
  if ! $CHANGED_CMDLINE && ! $CHANGED_MKINITCPIO; then
    log_info "Skipping initramfs rebuild; configuration is unchanged"
    return 0
  fi

  as_root mkinitcpio -P
  log_ok "Rebuilt initramfs/UKI artifacts"
}

verify_configuration() {
  local cmdline

  if $DRY_RUN && [[ -z $RESUME_OFFSET ]]; then
    log_info "[dry-run] Skipping resume parameter and active swap verification"
    return 0
  fi

  cmdline="$(as_root_readonly tr '\n' ' ' <"$CMDLINE_FILE")"
  [[ $cmdline == *"resume=UUID=${ROOT_UUID}"* ]] || die "verification failed: resume UUID is absent from ${CMDLINE_FILE}"
  [[ $cmdline == *"resume_offset=${RESUME_OFFSET}"* ]] || die "verification failed: resume offset is absent from ${CMDLINE_FILE}"
  grep -Eq '^[[:space:]]*HOOKS=\([^)]*\bresume\b[^)]*\)' "$MKINITCPIO_CONF" || die "verification failed: resume hook is absent from ${MKINITCPIO_CONF}"

  if $DRY_RUN; then
    log_info "[dry-run] Skipping active swap verification"
  else
    as_root_readonly swapon --noheadings --show=NAME | grep -Fx "$SWAPFILE" >/dev/null || die "verification failed: ${SWAPFILE} is not active"
  fi

  log_ok "Verified swap, kernel command line, and mkinitcpio configuration"
}

main() {
  parse_args "$@"
  preflight
  create_swapfile
  add_fstab_entry
  update_kernel_cmdline
  ensure_resume_hook
  rebuild_initramfs
  verify_configuration

  if $DRY_RUN; then
    log_warn "[dry-run] No changes were applied"
  else
    log_warn "Hibernate is configured. Reboot before testing: sudo reboot"
  fi
}

main "$@"