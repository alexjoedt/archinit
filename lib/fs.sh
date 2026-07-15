#!/usr/bin/env bash
# lib/fs.sh — safe, backup-aware filesystem operations
# Requires: lib/core.sh, lib/log.sh sourced first.

[[ -n ${_ARCHINIT_FS:-} ]] && return 0
_ARCHINIT_FS=1

# ensure_dir DIR — create directory (and parents) if absent
ensure_dir() {
  local dir="$1"
  [[ -d $dir ]] && return 0
  run mkdir -p "$dir"
}

# backup PATH — move an existing non-symlink to <path>.archinit.bak.<ts>
# No-op if PATH does not exist or is already a symlink.
backup() {
  local target="$1"
  [[ -e $target ]] || return 0 # nothing to back up
  [[ -L $target ]] && return 0 # already a symlink — skip

  local ts
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  local backup_path="${target}.archinit.bak.${ts}"
  log_info "fs: backing up ${target} -> ${backup_path}"
  run mv "$target" "$backup_path"
}

# symlink SRC DST — create a symlink DST -> SRC idempotently
# If DST already points correctly: no-op.
# If DST exists and is not the correct symlink: backup then replace.
symlink() {
  local src="$1"
  local dst="$2"

  # Already the correct symlink — no-op
  if [[ -L $dst ]] && [[ "$(readlink "$dst")" == "$src" ]]; then
    log_debug "fs: symlink already correct: $dst -> $src"
    return 0
  fi

  # Backup any existing file/dir/wrong-symlink at DST
  backup "$dst"
  # Remove a wrong symlink that backup() skipped (it was a symlink)
  if [[ -L $dst ]]; then
    run rm "$dst"
  fi

  ensure_dir "$(dirname "$dst")"
  log_info "fs: symlink $dst -> $src"
  run ln -s "$src" "$dst"
}
