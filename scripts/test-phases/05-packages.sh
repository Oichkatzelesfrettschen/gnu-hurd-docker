#!/bin/sh
# test-phases/05-packages.sh - Package Management Tests
# WHY: Verify apt package management functionality
# WHAT: Test package search and verification
# HOW: Use apt-cache search to verify package database

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=test-phases/common.sh
. "$SCRIPT_DIR/common.sh"

# Test: Package management functionality
test_packages() {
    echo ""
    echo_info "Phase 5: Testing package management (apt)..."
    
    echo "Testing apt-cache search:"
    if ssh_root 'apt-cache search gcc | head -5'; then
        echo_success "Package management working"
        return 0
    else
        echo_error "Package management test failed"
        return 1
    fi
}

# Run test if executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ] || [ "$0" = "sh" ] || [ "$0" = "bash" ]; then
    test_packages
    exit $?
fi
