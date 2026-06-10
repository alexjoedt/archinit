#!/usr/bin/env bash
# cmd/version.sh — print archinit version

cmd_version_help() {
  cat <<'EOF'
Usage: archinit version

Print the archinit version and git short SHA (if available).
EOF
}

cmd_version() {
  local version sha=""
  version="$(cat "${ARCHINIT_HOME}/VERSION" 2>/dev/null || echo "unknown")"
  version="${version%$'\n'}"

  if sha="$(git -C "${ARCHINIT_HOME}" rev-parse --short HEAD 2>/dev/null)"; then
    echo "archinit ${version} (${sha})"
  else
    echo "archinit ${version}"
  fi
}
