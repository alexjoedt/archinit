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

# Buffer used by 006_setup_hibernate_swap.sh (RAM + 10%).
BUFFER_PERCENT=10

NO_COLOR="${NO_COLOR:-0}"
QUIET=0
_START_TIME=$SECONDS

# Color variables — populated in main() after arg parsing.
_COLOR=0
_C_RESET='' _C_BOLD='' _C_DIM='' _C_INFO=''
_C_OK='' _C_WARN='' _C_ERROR='' _C_BLUE='' _C_MAGENTA=''
SYM_PASS='[OK]' SYM_WARN='[!!]' SYM_FAIL='[XX]'

_ID_WIDTH=36

usage() {
  cat <<'EOF'
Usage: 008_healthz.sh [OPTIONS]

Read-only health check for an Arch Linux + Hyprland laptop baseline.
Prints PASS / WARN / FAIL lines and exits:

  0  all checks PASS
  1  at least one WARN, zero FAIL
  2  at least one FAIL

Options:
  -h, --help       show this help and exit
  --no-color       disable color output (also respected via NO_COLOR=1)
  --quiet          suppress PASS lines; show only WARN and FAIL

Never installs packages, writes config, or changes systemd unit state.
EOF
}

log_info() { printf '%s[INFO]%s %s\n' "${_C_INFO}" "${_C_RESET}" "$*"; }

report() {
  local status="${1:?status required}"
  local id="${2:?id required}"
  local reason="${3:?reason required}"

  local sym color
  case "$status" in
    PASS) sym="$SYM_PASS"; color="$_C_OK"    ;;
    WARN) sym="$SYM_WARN"; color="$_C_WARN"  ;;
    FAIL) sym="$SYM_FAIL"; color="$_C_ERROR" ;;
    *)
      printf '%s[ERR ]%s internal: unknown status %s\n' \
        "$_C_ERROR" "$_C_RESET" "$status" >&2
      FAIL_COUNT=$((FAIL_COUNT + 1))
      return
      ;;
  esac

  if [[ $QUIET -eq 0 || $status != PASS ]]; then
    printf '%s%s%s  %s%-*s%s  %s\n' \
      "$color" "$sym" "$_C_RESET" \
      "$_C_DIM" "$_ID_WIDTH" "$id" "$_C_RESET" \
      "$reason"
  fi

  case "$status" in
    PASS) PASS_COUNT=$((PASS_COUNT + 1)) ;;
    WARN) WARN_COUNT=$((WARN_COUNT + 1)) ;;
    FAIL) FAIL_COUNT=$((FAIL_COUNT + 1)) ;;
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

# --- display helpers -----------------------------------------------------------

_repeat_char() {
  local char="${1:?char required}"
  local n="${2:?count required}"
  local result='' i
  for ((i = 0; i < n; i++)); do result+="$char"; done
  printf '%s' "$result"
}

section_header() {
  local title="${1:?title required}"
  local total_width=60
  local right_pad=$(( total_width - ${#title} - 5 ))
  [[ $right_pad -lt 4 ]] && right_pad=4

  if [[ $_COLOR -eq 1 ]]; then
    printf '\n%s%s─── %s %s%s\n' \
      "$_C_BOLD" "$_C_BLUE" \
      "$title" \
      "$(_repeat_char '─' "$right_pad")" \
      "$_C_RESET"
  else
    printf '\n--- %s %s\n' "$title" "$(_repeat_char '-' "$right_pad")"
  fi
}

print_header() {
  local hostname kernel uptime_str ram_str
  local inner_width=60

  hostname="$(hostname 2>/dev/null || printf 'unknown')"
  kernel="$(uname -r 2>/dev/null || printf 'unknown')"

  local uptime_sec
  uptime_sec="$(awk '{printf "%d", $1}' /proc/uptime 2>/dev/null || printf '0')"
  uptime_str="$(( uptime_sec / 3600 ))h $(( (uptime_sec % 3600) / 60 ))m"

  local ram_kib
  ram_kib="$(awk '/^MemTotal:/ { print $2; exit }' /proc/meminfo 2>/dev/null || printf '0')"
  ram_str="$(awk -v k="$ram_kib" 'BEGIN { printf "%.1f GiB", k / 1048576 }')"

  local title=" healthz — Arch + Hyprland baseline "
  local info="  host:${hostname}  kernel:${kernel}  up:${uptime_str}  ram:${ram_str}"

  if [[ $_COLOR -eq 1 ]]; then
    local bar
    bar="$(_repeat_char '═' "$inner_width")"

    printf '%s%s╔%s╗%s\n' "$_C_BOLD" "$_C_BLUE" "$bar" "$_C_RESET"

    local pad_total pad_l pad_r
    pad_total=$(( inner_width - ${#title} ))
    pad_l=$(( pad_total / 2 ))
    pad_r=$(( pad_total - pad_l ))
    printf '%s%s║%s%s%s%s%s%s║%s\n' \
      "$_C_BOLD" "$_C_BLUE" "$_C_RESET" \
      "$(_repeat_char ' ' "$pad_l")" \
      "${_C_BOLD}${title}${_C_RESET}" \
      "$(_repeat_char ' ' "$pad_r")" \
      "$_C_BOLD" "$_C_BLUE" "$_C_RESET"

    printf '%s%s╠%s╣%s\n' "$_C_BOLD" "$_C_BLUE" "$bar" "$_C_RESET"

    local info_pad
    info_pad=$(( inner_width - ${#info} ))
    [[ $info_pad -lt 0 ]] && info_pad=0
    printf '%s%s║%s%s%s%s%s║%s\n' \
      "$_C_BOLD" "$_C_BLUE" "$_C_RESET" \
      "$info" \
      "$(_repeat_char ' ' "$info_pad")" \
      "${_C_BOLD}${_C_BLUE}" "$_C_RESET"

    printf '%s%s╚%s╝%s\n' "$_C_BOLD" "$_C_BLUE" "$bar" "$_C_RESET"
  else
    local dash
    dash="$(_repeat_char '-' $(( inner_width + 2 )))"
    printf '%s\n' "$dash"
    printf ' healthz -- Arch + Hyprland baseline\n'
    printf '%s\n' "$dash"
    printf '%s\n' "$info"
    printf '%s\n' "$dash"
  fi
}

print_summary() {
  local elapsed=$(( SECONDS - _START_TIME ))
  local verdict verdict_color

  if (( FAIL_COUNT > 0 )); then
    verdict="DEGRADED"; verdict_color="$_C_ERROR"
  elif (( WARN_COUNT > 0 )); then
    verdict="WARNINGS"; verdict_color="$_C_WARN"
  else
    verdict="HEALTHY";  verdict_color="$_C_OK"
  fi

  if [[ $_COLOR -eq 1 ]]; then
    printf '\n%s%s─── Summary %s\n' "$_C_BOLD" "$_C_BLUE" "$_C_RESET"
    printf '  %s%sPASS%s %-4d  %s%sWARN%s %-4d  %s%sFAIL%s %-4d\n' \
      "$_C_OK"    "$_C_BOLD" "$_C_RESET" "$PASS_COUNT" \
      "$_C_WARN"  "$_C_BOLD" "$_C_RESET" "$WARN_COUNT" \
      "$_C_ERROR" "$_C_BOLD" "$_C_RESET" "$FAIL_COUNT"
    printf '\n  Verdict: %s%s%-8s%s  elapsed: %ds\n' \
      "$_C_BOLD" "$verdict_color" "$verdict" "$_C_RESET" "$elapsed"
  else
    printf '\n--- Summary\n'
    printf '  PASS %-4d  WARN %-4d  FAIL %-4d\n' \
      "$PASS_COUNT" "$WARN_COUNT" "$FAIL_COUNT"
    printf '  Verdict: %-8s  elapsed: %ds\n' "$verdict" "$elapsed"
  fi
}

# --- 1. Wayland / Hyprland session --------------------------------------------

check_session() {
  section_header "Wayland / Hyprland session"

  if [[ -n ${WAYLAND_DISPLAY:-} ]]; then
    report PASS "session:WAYLAND_DISPLAY" "WAYLAND_DISPLAY=${WAYLAND_DISPLAY}"
  else
    report FAIL "session:WAYLAND_DISPLAY" "WAYLAND_DISPLAY not set"
  fi

  local xdg="${XDG_SESSION_TYPE:-}"
  if [[ $xdg == wayland ]]; then
    report PASS "session:XDG_SESSION_TYPE" "XDG_SESSION_TYPE=wayland"
  elif [[ -z $xdg ]]; then
    report WARN "session:XDG_SESSION_TYPE" "XDG_SESSION_TYPE not set"
  else
    report FAIL "session:XDG_SESSION_TYPE" "XDG_SESSION_TYPE=${xdg} (expected wayland)"
  fi

  if have_cmd pgrep; then
    if pgrep -x Hyprland >/dev/null 2>&1; then
      report PASS "session:hyprland-proc" "Hyprland process running"
    else
      report WARN "session:hyprland-proc" "Hyprland process not found (not running inside Hyprland?)"
    fi
  else
    report WARN "session:hyprland-proc" "pgrep unavailable; skipped Hyprland process check"
  fi

  if have_cmd hyprctl; then
    local ver
    ver="$(hyprctl version -j 2>/dev/null \
           | grep -o '"tag":"[^"]*"' \
           | cut -d'"' -f4 \
           || true)"
    if [[ -n $ver ]]; then
      report PASS "session:hyprctl" "hyprctl available; version=${ver}"
    else
      report PASS "session:hyprctl" "hyprctl available (version tag not parsed)"
    fi
  else
    report WARN "session:hyprctl" "hyprctl not found"
  fi
}

# --- 2. Essential CLI packages -------------------------------------------------

check_cli_packages() {
  section_header "CLI packages"

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

# --- 3. Idle / lock stack ------------------------------------------------------

check_idle_stack() {
  section_header "Idle / lock stack"

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

  # Silence unused-var under set -u.
  : "${hypr_ok}" "${noct_conflict}"
}

# --- 4. logind lid handling ----------------------------------------------------

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
  section_header "logind lid handling"

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

# --- 5. Btrfs + snapper + snap-pac ---------------------------------------------

unit_is_enabled() {
  local unit="${1:?unit required}"
  systemctl is-enabled --quiet "$unit" 2>/dev/null
}

check_btrfs_snapper() {
  section_header "Btrfs + Snapper"

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

# --- 6. Hibernate swapfile -----------------------------------------------------

memory_kib() {
  [[ -r /proc/meminfo ]] || return 1
  awk '/^MemTotal:/ { print $2; exit }' /proc/meminfo
}

file_size_bytes() {
  local path="${1:?path required}"
  if have_cmd stat; then
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
  section_header "Hibernate swapfile"

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

  : "${active_ok}" "${has_hook}"
}

# --- 7. Audio / PipeWire -------------------------------------------------------

check_audio() {
  section_header "Audio / PipeWire"

  if have_cmd pgrep; then
    if pgrep -x pipewire >/dev/null 2>&1; then
      report PASS "audio:pipewire-proc" "pipewire process running"
    else
      report FAIL "audio:pipewire-proc" "pipewire process not running"
    fi

    if pgrep -x wireplumber >/dev/null 2>&1; then
      report PASS "audio:wireplumber-proc" "wireplumber process running"
    else
      report FAIL "audio:wireplumber-proc" "wireplumber process not running"
    fi
  else
    report WARN "audio:proc" "pgrep unavailable; skipped audio process checks"
  fi

  if have_cmd pacman; then
    local pkg
    for pkg in pipewire wireplumber; do
      if package_installed "$pkg"; then
        report PASS "audio:pkg:${pkg}" "package ${pkg} installed"
      else
        report FAIL "audio:pkg:${pkg}" "package ${pkg} not installed"
      fi
    done
  else
    report WARN "audio:pkg" "pacman unavailable; skipped audio package checks"
  fi
}

# --- 8. Systemd unit health ----------------------------------------------------

check_systemd_health() {
  section_header "Systemd unit health"

  if ! have_cmd systemctl; then
    report WARN "systemd:failed-units" "systemctl unavailable; skipped failed-unit check"
    return 0
  fi

  local failed_out
  failed_out="$(systemctl --failed --no-legend 2>/dev/null || true)"
  failed_out="$(printf '%s\n' "$failed_out" | grep -v '^[[:space:]]*$' || true)"

  if [[ -z $failed_out ]]; then
    report PASS "systemd:failed-units" "no failed systemd units"
    return 0
  fi

  local count
  count="$(printf '%s\n' "$failed_out" | wc -l)"
  count="${count//[[:space:]]/}"

  report FAIL "systemd:failed-units" "${count} failed unit(s)"

  local i=0 line unit_name
  while IFS= read -r line; do
    [[ -z $line ]] && continue
    i=$(( i + 1 ))
    if (( i <= 5 )); then
      unit_name="$(printf '%s' "$line" | awk '{print $1}')"
      report FAIL "systemd:unit:${unit_name}" "failed: ${line}"
    fi
  done <<< "$failed_out"

  if (( count > 5 )); then
    printf '  %s(+%d more — run: systemctl --failed)%s\n' \
      "$_C_DIM" "$(( count - 5 ))" "$_C_RESET"
  fi
}

# --- 9. Disk usage -------------------------------------------------------------

check_disk_usage() {
  section_header "Disk usage"

  if ! have_cmd df; then
    report WARN "disk:usage" "df unavailable; skipped disk usage checks"
    return 0
  fi

  local -a check_mounts=('/')

  local home_mp
  home_mp="$(df --output=target /home 2>/dev/null | tail -1 | xargs || true)"
  if [[ $home_mp == /home ]]; then
    check_mounts+=('/home')
  fi

  local mp used_pct size_info
  for mp in "${check_mounts[@]}"; do
    used_pct="$(df --output=pcent "$mp" 2>/dev/null \
                | tail -1 | tr -d ' %' || true)"

    if [[ ! $used_pct =~ ^[0-9]+$ ]]; then
      report WARN "disk:${mp}" "could not determine usage for ${mp}"
      continue
    fi

    size_info="$(df -h --output=size,used,avail "$mp" 2>/dev/null \
                 | tail -1 | xargs || true)"

    if (( used_pct >= 95 )); then
      report FAIL "disk:${mp}" "${mp} at ${used_pct}% (${size_info}) — critically full"
    elif (( used_pct >= 80 )); then
      report WARN "disk:${mp}" "${mp} at ${used_pct}% (${size_info})"
    else
      report PASS "disk:${mp}" "${mp} at ${used_pct}% (${size_info})"
    fi
  done
}

# --- 10. Pacman health ---------------------------------------------------------

check_pacman() {
  section_header "Pacman"

  if ! have_cmd pacman; then
    report WARN "pacman:available" "pacman not found; skipped all pacman checks"
    return 0
  fi

  # Lock file — indicates a stuck or in-progress transaction
  if [[ -e /var/lib/pacman/db.lck ]]; then
    report FAIL "pacman:lock" "/var/lib/pacman/db.lck present (stuck transaction? remove if no pacman running)"
  else
    report PASS "pacman:lock" "no pacman lock file"
  fi

  # Pending updates — reads local sync DB, no network call
  local update_count
  update_count="$(pacman -Qu 2>/dev/null | wc -l | tr -d ' ' || true)"
  if [[ ! $update_count =~ ^[0-9]+$ ]]; then
    report WARN "pacman:updates" "could not check for pending updates"
  elif (( update_count == 0 )); then
    report PASS "pacman:updates" "system up to date (local sync DB)"
  else
    report WARN "pacman:updates" "${update_count} package(s) pending update (run: pacman -Syu)"
  fi

  # Orphans — installed packages no longer required by anything
  local orphan_count orphan_list
  orphan_list="$(pacman -Qtdq 2>/dev/null || true)"
  orphan_count="$(printf '%s\n' "$orphan_list" | grep -c '[^[:space:]]' || true)"
  if (( orphan_count == 0 )); then
    report PASS "pacman:orphans" "no orphaned packages"
  else
    report WARN "pacman:orphans" "${orphan_count} orphan(s) (run: pacman -Rns \$(pacman -Qtdq))"
  fi

  # Pacnew files — config updates needing manual merge
  local pacnew_count pacnew_list
  pacnew_list="$(find /etc -name '*.pacnew' 2>/dev/null || true)"
  pacnew_count="$(printf '%s\n' "$pacnew_list" | grep -c '[^[:space:]]' || true)"
  if (( pacnew_count == 0 )); then
    report PASS "pacman:pacnew" "no .pacnew files in /etc"
  else
    report WARN "pacman:pacnew" "${pacnew_count} .pacnew file(s) need merge (run: pacdiff)"
  fi

  # AUR helper
  if have_cmd yay; then
    report PASS "pacman:aur-helper" "yay available"
  elif have_cmd paru; then
    report PASS "pacman:aur-helper" "paru available"
  else
    report WARN "pacman:aur-helper" "no AUR helper found (yay or paru)"
  fi
}

# --- main ----------------------------------------------------------------------

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      --no-color)
        NO_COLOR=1
        ;;
      --quiet)
        QUIET=1
        ;;
      *)
        usage
        printf '[ERR ] unknown option: %s\n' "$1" >&2
        exit 2
        ;;
    esac
    shift
  done

  if [[ -t 1 && ${NO_COLOR} != 1 && ${TERM:-} != dumb ]]; then
    _C_RESET=$'\033[0m'
    _C_BOLD=$'\033[1m'
    _C_DIM=$'\033[2m'
    _C_INFO=$'\033[36m'
    _C_OK=$'\033[32m'
    _C_WARN=$'\033[33m'
    _C_ERROR=$'\033[31m'
    _C_BLUE=$'\033[34m'
    _C_MAGENTA=$'\033[35m'
    _COLOR=1
    SYM_PASS=' ✓ '
    SYM_WARN=' ⚠ '
    SYM_FAIL=' ✗ '
  else
    _COLOR=0
  fi

  print_header

  check_session
  check_cli_packages
  check_idle_stack
  check_logind_lid
  check_btrfs_snapper
  check_hibernate_swap
  check_audio
  check_systemd_health
  check_disk_usage
  check_pacman

  print_summary

  if ((FAIL_COUNT > 0)); then
    exit 2
  fi
  if ((WARN_COUNT > 0)); then
    exit 1
  fi
  exit 0
}

main "$@"
