#!/usr/bin/env bash
# test-phases/01-infrastructure.sh - Container Infrastructure Tests
# WHY: Verify Docker container is running before other tests
# WHAT: Check container status and accessibility
# HOW: Use docker ps to verify gnu-hurd-dev container

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=test-phases/common.sh
. "$SCRIPT_DIR/common.sh"

# Test: Verify container is running
test_infrastructure() {
    echo ""
    echo_info "Phase 1: Verifying GNU/Hurd container infrastructure..."
    
    if docker ps | grep -q "gnu-hurd-dev"; then
        echo_success "Container is running"
        docker ps | grep gnu-hurd-dev
        return 0
    else
        echo_error "Container is not running"
        echo "Start with: docker compose up -d"
        return 1
    fi
}

# Run test if executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ] || [ "$0" = "sh" ] || [ "$0" = "bash" ]; then
    test_infrastructure
    exit $?
fi
