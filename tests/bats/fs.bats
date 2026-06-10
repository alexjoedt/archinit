#!/usr/bin/env bats
# tests/bats/fs.bats — unit tests for lib/fs.sh

setup() {
  export ARCHINIT_HOME
  ARCHINIT_HOME="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"

  export TEST_DIR
  TEST_DIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ---------------------------------------------------------------------------
# ensure_dir
# ---------------------------------------------------------------------------
@test "ensure_dir creates directory" {
  local target="${TEST_DIR}/a/b/c"
  bash -c "
    ARCHINIT_HOME='${ARCHINIT_HOME}'
    source '${ARCHINIT_HOME}/lib/core.sh'
    source '${ARCHINIT_HOME}/lib/log.sh'
    source '${ARCHINIT_HOME}/lib/fs.sh'
    ensure_dir '${target}'
  "
  [ -d "$target" ]
}

@test "ensure_dir is idempotent" {
  local target="${TEST_DIR}/idempotent"
  mkdir -p "$target"
  bash -c "
    ARCHINIT_HOME='${ARCHINIT_HOME}'
    source '${ARCHINIT_HOME}/lib/core.sh'
    source '${ARCHINIT_HOME}/lib/log.sh'
    source '${ARCHINIT_HOME}/lib/fs.sh'
    ensure_dir '${target}'
  "
  [ -d "$target" ]
}

# ---------------------------------------------------------------------------
# backup
# ---------------------------------------------------------------------------
@test "backup renames existing file with .archinit.bak suffix" {
  local target="${TEST_DIR}/original.conf"
  echo "content" > "$target"

  bash -c "
    ARCHINIT_HOME='${ARCHINIT_HOME}'
    source '${ARCHINIT_HOME}/lib/core.sh'
    source '${ARCHINIT_HOME}/lib/log.sh'
    source '${ARCHINIT_HOME}/lib/fs.sh'
    backup '${target}'
  "

  # Original should be gone (renamed)
  [ ! -f "$target" ]
  # A backup file should exist
  local count
  count="$(ls "${TEST_DIR}" | grep -c '\.archinit\.bak\.' || true)"
  [ "$count" -ge 1 ]
}

@test "backup is a no-op for symlinks" {
  local real="${TEST_DIR}/real.conf"
  local link="${TEST_DIR}/link.conf"
  echo "content" > "$real"
  ln -s "$real" "$link"

  bash -c "
    ARCHINIT_HOME='${ARCHINIT_HOME}'
    source '${ARCHINIT_HOME}/lib/core.sh'
    source '${ARCHINIT_HOME}/lib/log.sh'
    source '${ARCHINIT_HOME}/lib/fs.sh'
    backup '${link}'
  "

  # Symlink should still exist unchanged
  [ -L "$link" ]
}

# ---------------------------------------------------------------------------
# symlink
# ---------------------------------------------------------------------------
@test "symlink creates a symlink" {
  local src="${TEST_DIR}/src.conf"
  local dst="${TEST_DIR}/dst.conf"
  echo "hello" > "$src"

  bash -c "
    ARCHINIT_HOME='${ARCHINIT_HOME}'
    source '${ARCHINIT_HOME}/lib/core.sh'
    source '${ARCHINIT_HOME}/lib/log.sh'
    source '${ARCHINIT_HOME}/lib/fs.sh'
    symlink '${src}' '${dst}'
  "

  [ -L "$dst" ]
  [[ "$(readlink "$dst")" == "$src" ]]
}

@test "symlink is a no-op when already correct" {
  local src="${TEST_DIR}/src2.conf"
  local dst="${TEST_DIR}/dst2.conf"
  echo "hello" > "$src"
  ln -s "$src" "$dst"

  # No backup should be created on second run
  bash -c "
    ARCHINIT_HOME='${ARCHINIT_HOME}'
    source '${ARCHINIT_HOME}/lib/core.sh'
    source '${ARCHINIT_HOME}/lib/log.sh'
    source '${ARCHINIT_HOME}/lib/fs.sh'
    symlink '${src}' '${dst}'
  "

  [ -L "$dst" ]
  # No extra .bak files
  local bak_count
  bak_count="$(ls "${TEST_DIR}" | grep -c '\.archinit\.bak\.' || true)"
  [ "$bak_count" -eq 0 ]
}

@test "symlink backs up existing non-symlink file before creating link" {
  local src="${TEST_DIR}/src3.conf"
  local dst="${TEST_DIR}/dst3.conf"
  echo "new" > "$src"
  echo "old" > "$dst"   # existing regular file

  bash -c "
    ARCHINIT_HOME='${ARCHINIT_HOME}'
    source '${ARCHINIT_HOME}/lib/core.sh'
    source '${ARCHINIT_HOME}/lib/log.sh'
    source '${ARCHINIT_HOME}/lib/fs.sh'
    symlink '${src}' '${dst}'
  "

  [ -L "$dst" ]
  # A backup of the old file should exist
  local bak_count
  bak_count="$(ls "${TEST_DIR}" | grep -c 'dst3.*\.archinit\.bak\.' || true)"
  [ "$bak_count" -ge 1 ]
}
