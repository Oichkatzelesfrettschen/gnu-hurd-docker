#!/bin/bash
set -euo pipefail

# Compatibility wrapper: VBox automation is now conceptual-only.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/automation/stubs/vbox-conceptual-stub.sh" "$@"
