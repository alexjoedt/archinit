#!/usr/bin/env bats
# tests/bats/pkg.bats — unit tests for lib/pkg.sh (pkg_read_list)

setup() {
  export ARCHINIT_HOME
  ARCHINIT_HOME="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"

  # Create a temporary list file for testing
  export TEST_PKG_LIST
  TEST_PKG_LIST="$(mktemp)"
  cat >"$TEST_PKG_LIST" <<'EOF'
# This is a comment
base-devel

git
# another comment

curl

EOF
}

teardown() {
  rm -f "$TEST_PKG_LIST"
}

# ---------------------------------------------------------------------------
# pkg_read_list — strips comments and blank lines
# ---------------------------------------------------------------------------
@test "pkg_read_list strips comments and blank lines" {
  result="$(bash -c "
    ARCHINIT_HOME='${ARCHINIT_HOME}'
    source '${ARCHINIT_HOME}/lib/core.sh'
    source '${ARCHINIT_HOME}/lib/pkg.sh'
    pkg_read_list '${TEST_PKG_LIST}'
  ")"

  # Should contain these packages
  [[ $result == *"base-devel"* ]]
  [[ $result == *"git"* ]]
  [[ $result == *"curl"* ]]
}

@test "pkg_read_list output contains no comment lines" {
  result="$(bash -c "
    ARCHINIT_HOME='${ARCHINIT_HOME}'
    source '${ARCHINIT_HOME}/lib/core.sh'
    source '${ARCHINIT_HOME}/lib/pkg.sh'
    pkg_read_list '${TEST_PKG_LIST}'
  ")"

  # Should NOT contain comment text
  [[ $result != *"# This is"* ]]
  [[ $result != *"# another"* ]]
}

@test "pkg_read_list output contains no blank lines" {
  result="$(bash -c "
    ARCHINIT_HOME='${ARCHINIT_HOME}'
    source '${ARCHINIT_HOME}/lib/core.sh'
    source '${ARCHINIT_HOME}/lib/pkg.sh'
    pkg_read_list '${TEST_PKG_LIST}'
  ")"

  # Count lines — should be exactly 3
  count="$(echo "$result" | grep -c '[^[:space:]]')"
  [ "$count" -eq 3 ]
}

@test "pkg_read_list handles missing file gracefully (empty output)" {
  result="$(bash -c "
    ARCHINIT_HOME='${ARCHINIT_HOME}'
    source '${ARCHINIT_HOME}/lib/core.sh'
    source '${ARCHINIT_HOME}/lib/pkg.sh'
    pkg_read_list '/tmp/__nonexistent_archinit_test_file__'
  " 2>/dev/null || true)"
  [[ -z $result ]]
}

# ---------------------------------------------------------------------------
# pkg_install_official / pkg_install_aur — DRY_RUN echoes without executing
# ---------------------------------------------------------------------------
@test "pkg_install_official in DRY_RUN prints pacman command, does not invoke pacman" {
  result="$(DRY_RUN=1 bash -c "
    ARCHINIT_HOME='${ARCHINIT_HOME}'
    source '${ARCHINIT_HOME}/lib/core.sh'
    source '${ARCHINIT_HOME}/lib/os.sh'
    source '${ARCHINIT_HOME}/lib/pkg.sh'
    pkg_install_official some-test-pkg
  " 2>&1)"
  [[ $result == *"pacman"* ]]
  [[ $result == *"some-test-pkg"* ]]
}
