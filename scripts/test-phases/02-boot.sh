#!/bin/sh
# test-phases/02-boot.sh - Boot Process Verification
# WHY: Ensure system has fully booted and SSH is accessible
# WHAT: Wait for SSH port to become available with timeout
# HOW: Use nc to check SSH port accessibility

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=test-phases/common.sh
. "$SCRIPT_DIR/common.sh"

# Configuration
TIMEOUT="${TIMEOUT:-300}"  # 5 minutes default

# Test: Wait for system boot completion
test_boot() {
    echo ""
    echo_info "Phase 2: Waiting for system to boot (timeout: ${TIMEOUT}s)..."
    
    local start_time elapsed
    start_time=$(date +%s)
    elapsed=0
    
    while [ $elapsed -lt $TIMEOUT ]; do
        # Check if SSH port is open
        if nc -zv -w 2 "$SSH_HOST" "$SSH_PORT" 2>/dev/null; then
            echo_success "System booted - SSH port is accessible"
            elapsed=$(($(date +%s) - start_time))
            echo "Boot time: ${elapsed} seconds"
            return 0
        fi
        
        sleep 5
        elapsed=$(($(date +%s) - start_time))
        echo "  Waiting for boot... (${elapsed}/${TIMEOUT}s)"
    done
    
    echo_error "Boot timeout after ${TIMEOUT} seconds"
    return 1
}

# Run test if executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ] || [ "$0" = "sh" ] || [ "$0" = "bash" ]; then
    test_boot
    exit $?
fi
