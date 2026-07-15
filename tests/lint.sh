#!/usr/bin/env bash
# tests/lint.sh — run shellcheck and shfmt over all shell scripts

set -euo pipefail

ARCHINIT_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ARCHINIT_HOME"

FAILED=0

_fail() {
  echo "FAIL: $1" >&2
  FAILED=1
}

# ---------------------------------------------------------------------------
# shellcheck
# ---------------------------------------------------------------------------
echo "=== shellcheck ==="
if ! command -v shellcheck &>/dev/null; then
  echo "shellcheck not found; skipping (install with: pacman -S shellcheck)" >&2
else
  # Collect all shell files
  mapfile -t SHELL_FILES < <(
    find bin lib cmd modules install.sh shell \
      -type f \( -name "*.sh" -o -name "archinit" \) \
      | sort
  )

  if shellcheck "${SHELL_FILES[@]}"; then
    echo "shellcheck: PASS"
  else
    _fail "shellcheck reported issues"
  fi
fi

# ---------------------------------------------------------------------------
# shfmt
# ---------------------------------------------------------------------------
echo ""
echo "=== shfmt ==="
if ! command -v shfmt &>/dev/null; then
  echo "shfmt not found; skipping (install with: go install mvdan.cc/sh/v3/cmd/shfmt@latest)" >&2
else
  if shfmt -d -i 2 -ci \
      bin/ lib/ cmd/ modules/ install.sh shell/; then
    echo "shfmt: PASS"
  else
    _fail "shfmt found formatting differences (run: shfmt -w -i 2 -ci <files>)"
  fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
if [[ $FAILED -eq 0 ]]; then
  echo "All lint checks passed."
  exit 0
else
  echo "One or more lint checks FAILED." >&2
  exit 1
fi
