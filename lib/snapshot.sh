#!/usr/bin/env bash
# lib/snapshot.sh — package snapshot capture and restore (XDG state)
# Requires: lib/core.sh, lib/log.sh, lib/os.sh, lib/pkg.sh sourced first.

[[ -n ${_ARCHINIT_SNAPSHOT:-} ]] && return 0
_ARCHINIT_SNAPSHOT=1

_SNAPSHOT_DIR="${ARCHINIT_STATE}/snapshots"

# ---------------------------------------------------------------------------
# snapshot_create — capture current explicit packages to a timestamped dir
# ---------------------------------------------------------------------------
snapshot_create() {
  local ts
  ts="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
  local snap_dir="${_SNAPSHOT_DIR}/${ts}"

  if [[ -n ${DRY_RUN:-} ]]; then
    echo "[dry-run] snapshot_create: would write ${snap_dir}/{native,foreign}.txt"
    return 0
  fi

  mkdir -p "$snap_dir"

  pacman -Qqen >"${snap_dir}/native.txt"
  pacman -Qqem >"${snap_dir}/foreign.txt"

  # Atomic symlink update: latest -> <ts>
  ln -sfn "$ts" "${_SNAPSHOT_DIR}/latest"

  log_ok "snapshot: created ${snap_dir}"
  log_info "snapshot: native packages: $(wc -l <"${snap_dir}/native.txt")"
  log_info "snapshot: foreign packages: $(wc -l <"${snap_dir}/foreign.txt")"
}

# ---------------------------------------------------------------------------
# snapshot_list — list snapshot dirs newest-first, marking latest
# ---------------------------------------------------------------------------
snapshot_list() {
  [[ -d $_SNAPSHOT_DIR ]] || {
    echo "No snapshots found."
    return 0
  }

  local latest_ts=""
  if [[ -L "${_SNAPSHOT_DIR}/latest" ]]; then
    latest_ts="$(readlink "${_SNAPSHOT_DIR}/latest")"
  fi

  # List subdirs sorted newest-first
  local dir
  while IFS= read -r dir; do
    local name
    name="$(basename "$dir")"
    if [[ $name == "$latest_ts" ]]; then
      printf '%s  (latest)\n' "$name"
    else
      printf '%s\n' "$name"
    fi
  done < <(find "$_SNAPSHOT_DIR" -mindepth 1 -maxdepth 1 -type d | sort -r)
}

# ---------------------------------------------------------------------------
# snapshot_latest — print the name of the latest snapshot, or empty
# ---------------------------------------------------------------------------
snapshot_latest() {
  if [[ -L "${_SNAPSHOT_DIR}/latest" ]]; then
    readlink "${_SNAPSHOT_DIR}/latest"
  else
    echo ""
  fi
}

# ---------------------------------------------------------------------------
# snapshot_exists — return 0 if at least one snapshot exists
# ---------------------------------------------------------------------------
snapshot_exists() {
  [[ -L "${_SNAPSHOT_DIR}/latest" ]] && [[ -d "${_SNAPSHOT_DIR}/$(readlink "${_SNAPSHOT_DIR}/latest")" ]]
}

# ---------------------------------------------------------------------------
# snapshot_restore [NAME] — reinstall packages from named or latest snapshot
# ---------------------------------------------------------------------------
snapshot_restore() {
  local name="${1:-}"
  local snap_dir

  if [[ -z $name ]]; then
    snapshot_exists || die "snapshot_restore: no snapshot found. Run 'archinit snapshot' first."
    name="$(snapshot_latest)"
  fi

  snap_dir="${_SNAPSHOT_DIR}/${name}"
  [[ -d $snap_dir ]] || die "snapshot_restore: snapshot not found: ${snap_dir}"

  local native_file="${snap_dir}/native.txt"
  local foreign_file="${snap_dir}/foreign.txt"

  log_info "snapshot: restoring from ${name}"

  # Restore official packages
  if [[ -f $native_file ]]; then
    local -a native_pkgs
    mapfile -t native_pkgs < <(grep -v '^\s*$' "$native_file")
    if [[ ${#native_pkgs[@]} -gt 0 ]]; then
      log_info "snapshot: reinstalling ${#native_pkgs[@]} native packages"
      pkg_install_official "${native_pkgs[@]}"
    fi
  fi

  # Restore AUR packages
  if [[ -f $foreign_file ]]; then
    local -a foreign_pkgs
    mapfile -t foreign_pkgs < <(grep -v '^\s*$' "$foreign_file")
    if [[ ${#foreign_pkgs[@]} -gt 0 ]]; then
      has_aur_helper || die "snapshot_restore: AUR helper required for foreign packages. Run 'archinit install aur-helper' first."
      log_info "snapshot: reinstalling ${#foreign_pkgs[@]} foreign (AUR) packages"
      pkg_install_aur "${foreign_pkgs[@]}"
    fi
  fi

  log_ok "snapshot: restore complete"
}

# ---------------------------------------------------------------------------
# snapshot_native_packages — print native package names from latest snapshot
# ---------------------------------------------------------------------------
snapshot_native_packages() {
  snapshot_exists || return 0
  local latest snap_dir f
  latest="$(snapshot_latest)"
  snap_dir="${_SNAPSHOT_DIR}/${latest}"
  f="${snap_dir}/native.txt"
  if [[ -f $f ]]; then grep -v '^\s*$' "$f" || true; fi
}

# ---------------------------------------------------------------------------
# snapshot_foreign_packages — print foreign (AUR) package names from latest snapshot
# ---------------------------------------------------------------------------
snapshot_foreign_packages() {
  snapshot_exists || return 0
  local latest snap_dir f
  latest="$(snapshot_latest)"
  snap_dir="${_SNAPSHOT_DIR}/${latest}"
  f="${snap_dir}/foreign.txt"
  if [[ -f $f ]]; then grep -v '^\s*$' "$f" || true; fi
}
