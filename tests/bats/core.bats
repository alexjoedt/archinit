#!/usr/bin/env bats
# tests/bats/core.bats — unit tests for lib/core.sh

setup() {
  export ARCHINIT_HOME
  ARCHINIT_HOME="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"

  # Source in a subshell context via helper
  load_core() {
    source "${ARCHINIT_HOME}/lib/core.sh"
  }
}

# ---------------------------------------------------------------------------
# run() helper — dry-run mode echoes without executing
# ---------------------------------------------------------------------------
@test "run() in DRY_RUN mode prints command, does not execute" {
  result="$(DRY_RUN=1 bash -c "
    ARCHINIT_HOME='${ARCHINIT_HOME}'
    source '${ARCHINIT_HOME}/lib/core.sh'
    run echo 'should not execute'
  ")"
  [[ $result == *"echo"*"should not execute"* ]]
}

@test "run() without DRY_RUN executes the command" {
  result="$(bash -c "
    ARCHINIT_HOME='${ARCHINIT_HOME}'
    source '${ARCHINIT_HOME}/lib/core.sh'
    run echo 'executed'
  ")"
  [[ $result == "executed" ]]
}

# ---------------------------------------------------------------------------
# die()
# ---------------------------------------------------------------------------
@test "die() exits non-zero with message" {
  run bash -c "
    ARCHINIT_HOME='${ARCHINIT_HOME}'
    source '${ARCHINIT_HOME}/lib/core.sh'
    die 'test error'
  "
  [ "$status" -ne 0 ]
  [[ "$output" == *"test error"* ]]
}

# ---------------------------------------------------------------------------
# require_cmd()
# ---------------------------------------------------------------------------
@test "require_cmd() succeeds for existing command" {
  bash -c "
    ARCHINIT_HOME='${ARCHINIT_HOME}'
    source '${ARCHINIT_HOME}/lib/core.sh'
    require_cmd bash
  "
}

@test "require_cmd() dies for missing command" {
  run bash -c "
    ARCHINIT_HOME='${ARCHINIT_HOME}'
    source '${ARCHINIT_HOME}/lib/core.sh'
    require_cmd __archinit_nonexistent_cmd_xyz__
  "
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# is_root()
# ---------------------------------------------------------------------------
@test "is_root() returns 1 when not root" {
  if [[ $(id -u) -eq 0 ]]; then
    skip "Running as root"
  fi
  run bash -c "
    ARCHINIT_HOME='${ARCHINIT_HOME}'
    source '${ARCHINIT_HOME}/lib/core.sh'
    is_root
  "
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# Double-source guard
# ---------------------------------------------------------------------------
@test "core.sh double-source guard works" {
  result="$(bash -c "
    ARCHINIT_HOME='${ARCHINIT_HOME}'
    source '${ARCHINIT_HOME}/lib/core.sh'
    source '${ARCHINIT_HOME}/lib/core.sh'
    echo ok
  ")"
  [[ $result == "ok" ]]
}
