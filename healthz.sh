#!/usr/bin/env bash
#
# healthz — read-only Arch + Hyprland laptop health check
# Never mutates the system; reports PASS / WARN / FAIL only.
#

set -euo pipefail
IFS=$'\n\t'

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

SWAPFILE="/swap/swapfile"
FSTAB_FILE="/etc/fstab"
CMDLINE_FILE="/etc/kernel/cmdline"
MKINITCPIO_CONF="/etc/mkinitcpio.conf"
HYPRIDLE_CONF="${HOME}/.config/hypr/hypridle.conf"
HYPRLOCK_CONF="${HOME}/.config/hypr/hyprlock.conf"
NOCTIALIA_DIR="${HOME}/.config/noctialia"
SNAPPER_ROOT_CONFIG="/etc/snapper/configs/root"

# Buffer used by setup_hibernate_swap.sh (RAM + 10%).
BUFFER_PERCENT=10

usage() {
  cat <<'EOF'
Usage: healthz.sh

Read-only health check for an Arch Linux + Hyprland laptop baseline.
Prints PASS / WARN / FAIL lines and exits:

  0  all checks PASS
  1  at least one WARN, zero FAIL
  2  at least one FAIL

Never installs packages, writes config, or changes systemd unit state.
EOF
}

log_info() { printf '[INFO] %s\n' "$*"; }

report() {
  local status="${1:?status required}"
  local id="${2:?id required}"
  local reason="${3:?reason required}"

  printf '%s  %s  %s\n' "$status" "$id" "$reason"

  case "$status" in
    PASS) PASS_COUNT=$((PASS_COUNT + 1)) ;;
    WARN) WARN_COUNT=$((WARN_COUNT + 1)) ;;
    FAIL) FAIL_COUNT=$((FAIL_COUNT + 1)) ;;
    *)
      printf '[ERR ] internal: unknown status %s\n' "$status" >&2
      FAIL_COUNT=$((FAIL_COUNT + 1))
      ;;
  esac
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

package_installed() {
  local pkg="${1:?package required}"
  if have_cmd pacman; then
    pacman -Q "$pkg" >/dev/null 2>&1
  else
    return 1
  fi
}

# --- 1. Essential CLI packages -------------------------------------------------

check_cli_packages() {
  local -a pkgs=(jq ripgrep fd)
  local -a bins=(jq rg fd)
  local i pkg bin

  for i in "${!pkgs[@]}"; do
    pkg="${pkgs[$i]}"
    bin="${bins[$i]}"

    if ! have_cmd "$bin"; then
      if package_installed "$pkg"; then
        report FAIL "cli:${pkg}" "package ${pkg} installed but binary '${bin}' not on PATH"
      else
        report FAIL "cli:${pkg}" "package ${pkg} / binary '${bin}' missing"
      fi
      continue
    fi

    if have_cmd pacman; then
      if package_installed "$pkg"; then
        report PASS "cli:${pkg}" "package ${pkg} present; binary '${bin}' on PATH"
      else
        report WARN "cli:${pkg}" "binary '${bin}' on PATH but pacman does not list package ${pkg}"
      fi
    else
      report PASS "cli:${pkg}" "binary '${bin}' on PATH"
    fi
  done
}

# --- 2. Idle / lock stack ------------------------------------------------------

check_idle_stack() {
  local hypr_ok=true
  local noct_conflict=false

  if [[ -e $NOCTIALIA_DIR ]]; then
    noct_conflict=true
    if [[ -d $NOCTIALIA_DIR ]]; then
      report FAIL "idle:noctialia" "${NOCTIALIA_DIR}/ present (conflicting idle/suspend stack; prefer hypridle+hyprlock)"
    else
      report FAIL "idle:noctialia" "${NOCTIALIA_DIR} exists (conflicting idle/suspend stack)"
    fi
  else
    report PASS "idle:noctialia" "${NOCTIALIA_DIR} absent"
  fi

  if [[ -f $HYPRIDLE_CONF ]]; then
    report PASS "idle:hypridle.conf" "found ${HYPRIDLE_CONF}"
  else
    hypr_ok=false
    report FAIL "idle:hypridle.conf" "missing ${HYPRIDLE_CONF}"
  fi

  if [[ -f $HYPRLOCK_CONF ]]; then
    report PASS "idle:hyprlock.conf" "found ${HYPRLOCK_CONF}"
  else
    hypr_ok=false
    report FAIL "idle:hyprlock.conf" "missing ${HYPRLOCK_CONF}"
  fi

  if have_cmd pacman; then
    if package_installed hypridle; then
      report PASS "idle:pkg:hypridle" "package hypridle installed"
    else
      hypr_ok=false
      if [[ -f $HYPRIDLE_CONF ]]; then
        report FAIL "idle:pkg:hypridle" "hypridle.conf present but package hypridle not installed"
      else
        report FAIL "idle:pkg:hypridle" "package hypridle not installed"
      fi
    fi

    if package_installed hyprlock; then
      report PASS "idle:pkg:hyprlock" "package hyprlock installed"
    else
      hypr_ok=false
      if [[ -f $HYPRLOCK_CONF ]]; then
        report FAIL "idle:pkg:hyprlock" "hyprlock.conf present but package hyprlock not installed"
      else
        report FAIL "idle:pkg:hyprlock" "package hyprlock not installed"
      fi
    fi
  else
    report WARN "idle:pkg" "pacman unavailable; skipped hypridle/hyprlock package checks"
  fi

  if have_cmd pgrep; then
    if pgrep -x swayidle >/dev/null 2>&1; then
      report WARN "idle:swayidle" "swayidle is running; intended stack is hypridle"
    fi
  fi

  if $hypr_ok && ! $noct_conflict; then
    : # individual PACSes already recorded
  fi
}

# --- 3. logind lid handling ----------------------------------------------------

# Parse KEY=value from systemd drop-in style config; last assignment wins.
# stdin: concatenated conf text.
logind_effective_value() {
  local key="${1:?key required}"
  awk -v key="$key" '
    BEGIN { FS = "=" }
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    {
      line = $0
      sub(/[[:space:]]*#.*$/, "", line)
      sub(/^[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)
      if (line ~ ("^" key "=")) {
        val = line
        sub("^" key "=", "", val)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
        last = val
      }
    }
    END {
      if (last == "") exit 1
      print last
    }
  '
}

collect_logind_config() {
  local tmp
  tmp="$(mktemp)"

  if have_cmd systemd-analyze; then
    if systemd-analyze cat-config systemd/logind.conf >"$tmp" 2>/dev/null; then
      cat "$tmp"
      rm -f "$tmp"
      return 0
    fi
  fi

  {
    [[ -r /etc/systemd/logind.conf ]] && cat /etc/systemd/logind.conf
    if [[ -d /etc/systemd/logind.conf.d ]]; then
      local f
      for f in /etc/systemd/logind.conf.d/*.conf; do
        [[ -r $f ]] && cat "$f"
      done
    fi
  } >"$tmp" 2>/dev/null || true

  if [[ ! -s $tmp ]]; then
    rm -f "$tmp"
    return 1
  fi

  cat "$tmp"
  rm -f "$tmp"
  return 0
}

check_logind_lid() {
  local conf
  local handle handle_ext handle_dock
  local expected=ignore

  if ! conf="$(collect_logind_config)"; then
    report WARN "logind:config" "could not read logind.conf (permission or missing); needs root-free read of /etc/systemd/logind.conf*"
    return 0
  fi

  handle="$(logind_effective_value HandleLidSwitch <<<"$conf" || true)"
  handle_ext="$(logind_effective_value HandleLidSwitchExternalPower <<<"$conf" || true)"
  handle_dock="$(logind_effective_value HandleLidSwitchDocked <<<"$conf" || true)"

  # Empty means systemd default (suspend for HandleLidSwitch on laptops).
  if [[ -z $handle ]]; then
    handle="(default/unset→suspend)"
  fi
  if [[ -z $handle_ext ]]; then
    handle_ext="(default/unset)"
  fi
  if [[ -z $handle_dock ]]; then
    handle_dock="(default/unset)"
  fi

  if [[ $handle == "$expected" ]]; then
    report PASS "logind:HandleLidSwitch" "HandleLidSwitch=${handle}"
  else
    report FAIL "logind:HandleLidSwitch" "expected HandleLidSwitch=${expected}, found ${handle} (hypridle should own sleep)"
  fi

  if [[ $handle_ext == "$expected" ]]; then
    report PASS "logind:HandleLidSwitchExternalPower" "HandleLidSwitchExternalPower=${handle_ext}"
  else
    report FAIL "logind:HandleLidSwitchExternalPower" "expected HandleLidSwitchExternalPower=${expected}, found ${handle_ext}"
  fi

  if [[ $handle_dock == "$expected" ]]; then
    report PASS "logind:HandleLidSwitchDocked" "HandleLidSwitchDocked=${handle_dock}"
  else
    report FAIL "logind:HandleLidSwitchDocked" "expected HandleLidSwitchDocked=${expected}, found ${handle_dock}"
  fi

  if have_cmd loginctl; then
    local sessions
    sessions="$(loginctl list-sessions --no-legend 2>/dev/null || true)"
    if [[ -n $sessions ]]; then
      report PASS "logind:session" "loginctl shows at least one session"
    else
      if [[ ${EUID} -eq 0 ]]; then
        report WARN "logind:session" "no loginctl sessions visible (running as root?)"
      else
        report WARN "logind:session" "no loginctl sessions listed for this user"
      fi
    fi
  else
    report WARN "logind:session" "loginctl not available; skipped session sanity check"
  fi
}

# --- 4. Btrfs + snapper + snap-pac ---------------------------------------------

unit_is_enabled() {
  local unit="${1:?unit required}"
  systemctl is-enabled --quiet "$unit" 2>/dev/null
}

check_btrfs_snapper() {
  local fstype=""

  if have_cmd findmnt; then
    fstype="$(findmnt -no FSTYPE / 2>/dev/null || true)"
  elif [[ -r /proc/mounts ]]; then
    fstype="$(awk '$2 == "/" { print $3; exit }' /proc/mounts)"
  fi

  if [[ -z $fstype ]]; then
    report FAIL "fs:root" "could not determine root filesystem type"
    return 0
  fi

  if [[ $fstype != btrfs ]]; then
    report FAIL "fs:root" "root filesystem is ${fstype}, expected btrfs"
    return 0
  fi
  report PASS "fs:root" "root filesystem is btrfs"

  if have_cmd pacman; then
    if package_installed btrfs-progs; then
      report PASS "fs:pkg:btrfs-progs" "package btrfs-progs installed"
    else
      report WARN "fs:pkg:btrfs-progs" "package btrfs-progs not installed"
    fi

    if package_installed snapper; then
      report PASS "fs:pkg:snapper" "package snapper installed"
    else
      report FAIL "fs:pkg:snapper" "package snapper not installed"
    fi

    if package_installed snap-pac; then
      report PASS "fs:pkg:snap-pac" "package snap-pac installed"
    else
      report FAIL "fs:pkg:snap-pac" "package snap-pac not installed"
    fi
  else
    report WARN "fs:pkg" "pacman unavailable; skipped snapper/snap-pac package checks"
  fi

  if [[ -r $SNAPPER_ROOT_CONFIG ]]; then
    report PASS "fs:snapper:root-config" "found ${SNAPPER_ROOT_CONFIG}"
  elif [[ -e $SNAPPER_ROOT_CONFIG ]]; then
    report WARN "fs:snapper:root-config" "${SNAPPER_ROOT_CONFIG} exists but is unreadable"
  else
    if have_cmd pacman && package_installed snapper; then
      report FAIL "fs:snapper:root-config" "snapper installed but ${SNAPPER_ROOT_CONFIG} missing"
    else
      report FAIL "fs:snapper:root-config" "missing ${SNAPPER_ROOT_CONFIG}"
    fi
  fi

  if [[ -r /etc/conf.d/snapper ]]; then
    if grep -Eq '(^|[[:space:]])root([[:space:]]|$)' /etc/conf.d/snapper 2>/dev/null \
      || grep -Eq 'SNAPPER_CONFIGS=.*\broot\b' /etc/conf.d/snapper 2>/dev/null; then
      report PASS "fs:snapper:config-list" "root appears in /etc/conf.d/snapper"
    else
      report WARN "fs:snapper:config-list" "root not clearly listed in /etc/conf.d/snapper"
    fi
  fi

  if have_cmd systemctl; then
    local t
    for t in snapper-timeline.timer snapper-cleanup.timer; do
      if unit_is_enabled "$t"; then
        report PASS "fs:snapper:${t}" "${t} is enabled"
      else
        local state
        state="$(systemctl is-enabled "$t" 2>/dev/null || echo missing)"
        report WARN "fs:snapper:${t}" "${t} not enabled (state=${state})"
      fi
    done
  else
    report WARN "fs:snapper:timers" "systemctl unavailable; skipped snapper timer checks"
  fi
}

# --- 5. Hibernate swapfile -----------------------------------------------------

memory_kib() {
  [[ -r /proc/meminfo ]] || return 1
  awk '/^MemTotal:/ { print $2; exit }' /proc/meminfo
}

file_size_bytes() {
  local path="${1:?path required}"
  if have_cmd stat; then
    # GNU stat first, BSD fallback.
    stat -c '%s' "$path" 2>/dev/null || stat -f '%z' "$path" 2>/dev/null
  else
    wc -c <"$path" | tr -d ' '
  fi
}

format_kib() {
  local kib="${1:?KiB required}"
  awk -v kib="$kib" 'BEGIN {
    if (kib >= 1048576) printf "%.2f GiB", kib / 1048576
    else printf "%.2f MiB", kib / 1024
  }'
}

cmdline_blob() {
  local blob=""
  if [[ -r /proc/cmdline ]]; then
    blob+=" $(tr '\n' ' ' </proc/cmdline)"
  fi
  if [[ -r $CMDLINE_FILE ]]; then
    blob+=" $(tr '\n' ' ' <"$CMDLINE_FILE")"
  fi
  printf '%s' "$blob"
}

check_hibernate_swap() {
  local ram_kib mem_bytes min_bytes preferred_bytes size_bytes
  local fstab_ok=false active_ok=false
  local extra_swap=false
  local cmdline has_resume has_offset has_hook

  ram_kib="$(memory_kib || true)"
  if [[ ! $ram_kib =~ ^[0-9]+$ ]] || [[ $ram_kib -le 0 ]]; then
    report FAIL "swap:ram" "could not read MemTotal from /proc/meminfo"
    return 0
  fi

  mem_bytes=$((ram_kib * 1024))
  min_bytes=$((mem_bytes + 1))
  preferred_bytes=$(((ram_kib * (100 + BUFFER_PERCENT) + 99) * 1024 / 100))

  if [[ ! -e $SWAPFILE ]]; then
    report FAIL "swap:file" "missing ${SWAPFILE}"
  elif [[ ! -f $SWAPFILE && ! -b $SWAPFILE ]]; then
    report FAIL "swap:file" "${SWAPFILE} exists but is not a regular file"
  else
    size_bytes="$(file_size_bytes "$SWAPFILE" || true)"
    if [[ ! $size_bytes =~ ^[0-9]+$ ]]; then
      report WARN "swap:size" "could not determine size of ${SWAPFILE} (permission?)"
    elif ((size_bytes < min_bytes)); then
      report FAIL "swap:size" "${SWAPFILE} is $(format_kib "$((size_bytes / 1024))"), need > $(format_kib "$ram_kib") RAM"
    elif ((size_bytes < preferred_bytes)); then
      report WARN "swap:size" "${SWAPFILE} is $(format_kib "$((size_bytes / 1024))") (> RAM) but below preferred RAM+${BUFFER_PERCENT}% ($(format_kib "$((preferred_bytes / 1024))"))"
    else
      report PASS "swap:size" "${SWAPFILE} is $(format_kib "$((size_bytes / 1024))") (>= RAM+${BUFFER_PERCENT}% $(format_kib "$((preferred_bytes / 1024))"))"
    fi
  fi

  if [[ -r $FSTAB_FILE ]]; then
    if awk -v swapfile="$SWAPFILE" '
      $1 ~ /^#/ { next }
      $1 == swapfile && $3 == "swap" { found = 1 }
      END { exit !found }
    ' "$FSTAB_FILE"; then
      fstab_ok=true
      report PASS "swap:fstab" "${FSTAB_FILE} has swap entry for ${SWAPFILE}"
    else
      report FAIL "swap:fstab" "no swap entry for ${SWAPFILE} in ${FSTAB_FILE}"
    fi
  else
    report FAIL "swap:fstab" "${FSTAB_FILE} unreadable or missing"
  fi

  if have_cmd swapon; then
    local swapon_out
    swapon_out="$(swapon --noheadings --show=NAME 2>/dev/null || true)"
    if grep -Fxq "$SWAPFILE" <<<"$swapon_out"; then
      active_ok=true
      report PASS "swap:active" "${SWAPFILE} is active"
    else
      if $fstab_ok; then
        report WARN "swap:active" "${SWAPFILE} in fstab but not active (swapon?)"
      else
        report FAIL "swap:active" "${SWAPFILE} is not active swap"
      fi
    fi

    while IFS= read -r name; do
      [[ -z $name ]] && continue
      if [[ $name != "$SWAPFILE" ]]; then
        extra_swap=true
      fi
    done <<<"$swapon_out"

    if $extra_swap; then
      report WARN "swap:extra" "additional swap devices active besides ${SWAPFILE}: ${swapon_out//$'\n'/, }"
    fi
  else
    report WARN "swap:active" "swapon not available; skipped active-swap check"
  fi

  cmdline="$(cmdline_blob)"
  has_resume=false
  has_offset=false
  if [[ $cmdline == *"resume="* ]]; then
    has_resume=true
  fi
  if [[ $cmdline == *"resume_offset="* ]]; then
    has_offset=true
  fi

  if $has_resume && $has_offset; then
    report PASS "swap:resume-cmdline" "resume= and resume_offset= present in kernel cmdline"
  elif $has_resume && ! $has_offset; then
    report FAIL "swap:resume-cmdline" "resume= present but resume_offset= missing (file-based hibernate needs offset)"
  elif ! $has_resume && $has_offset; then
    report FAIL "swap:resume-cmdline" "resume_offset= present but resume= missing"
  else
    report FAIL "swap:resume-cmdline" "resume= / resume_offset= missing from /proc/cmdline and ${CMDLINE_FILE}"
  fi

  has_hook=false
  if [[ -r $MKINITCPIO_CONF ]]; then
    if grep -Eq '^[[:space:]]*HOOKS=\([^)]*\bresume\b[^)]*\)' "$MKINITCPIO_CONF"; then
      has_hook=true
      report PASS "swap:resume-hook" "mkinitcpio HOOKS includes resume"
    else
      report FAIL "swap:resume-hook" "mkinitcpio HOOKS missing resume in ${MKINITCPIO_CONF}"
    fi
  else
    if [[ -e $MKINITCPIO_CONF ]]; then
      report WARN "swap:resume-hook" "${MKINITCPIO_CONF} unreadable; needs permission to verify resume hook"
    else
      report FAIL "swap:resume-hook" "missing ${MKINITCPIO_CONF}"
    fi
  fi

  # Silence unused-var under set -u in edge paths.
  : "${active_ok}" "${has_hook}"
}

# --- main ----------------------------------------------------------------------

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      *)
        usage
        printf '[ERR ] unknown option: %s\n' "$1" >&2
        exit 2
        ;;
    esac
  done

  log_info "healthz — read-only Arch + Hyprland baseline check"
  log_info "host=$(hostname 2>/dev/null || echo unknown) user=${USER:-unknown} uid=${EUID}"
  printf '\n'

  check_cli_packages
  printf '\n'
  check_idle_stack
  printf '\n'
  check_logind_lid
  printf '\n'
  check_btrfs_snapper
  printf '\n'
  check_hibernate_swap
  printf '\n'

  printf '%s\n' '---'
  printf 'SUMMARY  PASS=%d  WARN=%d  FAIL=%d\n' "$PASS_COUNT" "$WARN_COUNT" "$FAIL_COUNT"

  if ((FAIL_COUNT > 0)); then
    exit 2
  fi
  if ((WARN_COUNT > 0)); then
    exit 1
  fi
  exit 0
}

main "$@"
