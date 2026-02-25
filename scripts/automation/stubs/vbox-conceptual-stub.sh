#!/bin/bash
set -euo pipefail

# VirtualBox conceptual stub: no operational automation.
# QEMU-first is the only supported execution path.

usage() {
    cat <<'EOF'
VirtualBox Conceptual Stub

Usage: scripts/vboxmanage-hurd.sh <command>

Supported conceptual commands:
  doctor
  create
  start
  stop
  status
  attach-iso
  detach-iso
  install-auto
  provision
  full-auto
  destroy

This path is intentionally non-operational.
Use QEMU-first automation instead:
  make qemu-full-auto
  make qemu-auto-verify
  make qemu-matrix
EOF
}

command_name="${1:-help}"
if [ "$#" -gt 0 ]; then
    shift
fi

case "$command_name" in
    help|-h|--help)
        usage
        ;;
    doctor|create|start|stop|status|attach-iso|detach-iso|install-auto|provision|full-auto|destroy)
        echo "[STUB] VirtualBox automation is currently conceptual-only."
        echo "[STUB] Requested command: ${command_name}"
        echo "[STUB] Use QEMU-first path: make qemu-full-auto | make qemu-auto-verify | make qemu-matrix"
        ;;
    *)
        echo "[STUB] Unknown VirtualBox command: ${command_name}" >&2
        usage >&2
        exit 2
        ;;
esac
