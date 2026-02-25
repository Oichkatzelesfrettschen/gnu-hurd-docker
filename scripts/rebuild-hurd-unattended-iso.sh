#!/bin/bash
set -euo pipefail

# Compatibility wrapper: canonical implementation lives under scripts/automation/qemu.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/automation/qemu/rebuild-hurd-unattended-iso.sh" "$@"
