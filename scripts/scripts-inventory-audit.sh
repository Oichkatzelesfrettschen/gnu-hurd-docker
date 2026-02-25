#!/bin/bash
set -euo pipefail

# Compatibility wrapper for script inventory/synthesis audit.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/automation/audit/audit-scripts-inventory.sh" "$@"
