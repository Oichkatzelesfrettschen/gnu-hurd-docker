#!/bin/bash
set -euo pipefail

# Run privileged commands through sudo askpass in non-interactive workflows.

ASKPASS_BIN="${SUDO_ASKPASS:-${SSH_ASKPASS:-/usr/bin/unified-askpass}}"

usage() {
    cat <<'EOF'
Usage: scripts/sudo-askpass.sh <command> [args...]

Examples:
  scripts/sudo-askpass.sh rcvboxdrv setup
  scripts/sudo-askpass.sh /sbin/vboxconfig
EOF
}

if [ $# -lt 1 ]; then
    usage >&2
    exit 2
fi

if [ ! -x "$ASKPASS_BIN" ]; then
    echo "[ERROR] Askpass helper not executable: $ASKPASS_BIN" >&2
    echo "        Set SUDO_ASKPASS to a valid askpass binary." >&2
    exit 1
fi

echo "[INFO] Using askpass helper: $ASKPASS_BIN"
SUDO_ASKPASS="$ASKPASS_BIN" sudo -A "$@"
