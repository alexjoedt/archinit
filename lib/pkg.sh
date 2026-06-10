#!/usr/bin/env bash
# lib/pkg.sh — idempotent, class-aware package installation
# Requires: lib/core.sh, lib/log.sh, lib/os.sh sourced first.

[[ -n ${_ARCHINIT_PKG:-} ]] && return 0
_ARCHINIT_PKG=1

# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_LOG:-} ]] || source "${ARCHINIT_HOME}/lib/log.sh"

# ---------------------------------------------------------------------------
# pkg_read_list FILE — print cleaned package names (strip comments & blanks)
# ---------------------------------------------------------------------------
pkg_read_list() {
  local file="$1"
  [[ -f $file ]] || die "pkg_read_list: file not found: $file"
  grep -v '^\s*#' "$file" | grep -v '^\s*$' | awk '{print $1}'
}

# ---------------------------------------------------------------------------
# _pkg_install_one_official PKG — install a single official package; return exit code
# ---------------------------------------------------------------------------
_pkg_install_one_official() {
  local pkg="$1"
  if pkg_is_installed "$pkg"; then
    log_debug "pkg: $pkg already installed, skipping"
    return 0
  fi
  run as_root pacman -S --needed --noconfirm "$pkg"
}

# ---------------------------------------------------------------------------
# _pkg_install_one_aur PKG — install a single AUR package; return exit code
# ---------------------------------------------------------------------------
_pkg_install_one_aur() {
  local pkg="$1"
  local helper
  helper="$(aur_helper)"
  if pkg_is_installed "$pkg"; then
    log_debug "pkg(aur): $pkg already installed, skipping"
    return 0
  fi
  run "$helper" -S --needed --noconfirm "$pkg"
}

# ---------------------------------------------------------------------------
# _pkg_install_batch INSTALLER PKG... — try batch first, fall back per-package
# Returns: 0 if all succeeded; 1 if any failed (failures reported to caller)
# Sets _PKG_FAILURES (array) in caller's scope via nameref — callers must
# declare: local -a _PKG_FAILURES=()
# ---------------------------------------------------------------------------
_pkg_batch_with_fallback() {
  local mode="$1" # "official" or "aur"
  shift
  local -a pkgs=("$@")
  local -a failures=()

  if [[ ${#pkgs[@]} -eq 0 ]]; then
    return 0
  fi

  # Try batch first (fast path)
  if [[ $mode == "official" ]]; then
    if run as_root pacman -S --needed --noconfirm "${pkgs[@]}" 2>/dev/null; then
      return 0
    fi
  else
    local helper
    helper="$(aur_helper)"
    if run "$helper" -S --needed --noconfirm "${pkgs[@]}" 2>/dev/null; then
      return 0
    fi
  fi

  # Batch failed — fall back to per-package to isolate failures
  log_warn "pkg: batch install failed; retrying per-package"
  local pkg
  for pkg in "${pkgs[@]}"; do
    if [[ $mode == "official" ]]; then
      if ! _pkg_install_one_official "$pkg"; then
        failures+=("$pkg")
        log_warn "pkg: failed to install: $pkg"
      fi
    else
      if ! _pkg_install_one_aur "$pkg"; then
        failures+=("$pkg")
        log_warn "pkg(aur): failed to install: $pkg"
      fi
    fi
  done

  if [[ ${#failures[@]} -gt 0 ]]; then
    log_error "pkg: ${#failures[@]} package(s) failed: ${failures[*]}"
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# pkg_install_official PKG... — install official packages with failure summary
# ---------------------------------------------------------------------------
pkg_install_official() {
  [[ $# -gt 0 ]] || return 0
  _pkg_batch_with_fallback official "$@"
}

# ---------------------------------------------------------------------------
# pkg_install_aur PKG... — install AUR packages with failure summary
# ---------------------------------------------------------------------------
pkg_install_aur() {
  [[ $# -gt 0 ]] || return 0
  has_aur_helper || die "No AUR helper found. Run the 'aur-helper' module first."
  _pkg_batch_with_fallback aur "$@"
}

# ---------------------------------------------------------------------------
# pkg_install_list CLASS — install all packages from config/packages/<CLASS>.txt
# CLASS: base | desktop | aur
# ---------------------------------------------------------------------------
pkg_install_list() {
  local class="$1"
  local list_file="${ARCHINIT_HOME}/config/packages/${class}.txt"
  [[ -f $list_file ]] || die "pkg_install_list: no package list for class '${class}' at ${list_file}"

  local -a pkgs
  mapfile -t pkgs < <(pkg_read_list "$list_file")

  if [[ ${#pkgs[@]} -eq 0 ]]; then
    log_info "pkg: no packages in list '${class}'"
    return 0
  fi

  log_info "pkg: installing ${#pkgs[@]} ${class} package(s)"

  if [[ $class == "aur" ]]; then
    pkg_install_aur "${pkgs[@]}"
  else
    pkg_install_official "${pkgs[@]}"
  fi
}
