#!/bin/bash
# =============================================================================
# Health Check Script for GNU/Hurd x86_64 QEMU Container
# =============================================================================
# PURPOSE:
# - Verify QEMU process is running
# - Check if SSH port is accessible (guest may still be booting)
# - Check if HTTP port is accessible
# - Exit 0 if healthy, exit 1 if unhealthy
# =============================================================================

set -euo pipefail

# Source libraries
# shellcheck source=lib/colors.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/colors.sh"
# shellcheck source=lib/container-helpers.sh
source "$SCRIPT_DIR/lib/container-helpers.sh"

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_FAILURE=1

# Ports to check
readonly SSH_PORT=2222
readonly HTTP_PORT=8080

# Logging functions (adapted to use library functions)
log_error() {
    echo_error "$1" >&2
}

log_success() {
    echo_success "$1"
}

log_info() {
    echo_info "$1"
}

# Check if QEMU process is running (x86_64 binary specifically)
check_qemu_process() {
    if pgrep -f "qemu-system-x86_64" > /dev/null 2>&1; then
        log_success "QEMU x86_64 process is running"
        return 0
    else
        log_error "QEMU x86_64 process is not running"
        return 1
    fi
}

# Check if SSH port is accessible
check_ssh_port() {
    if nc -zv localhost "$SSH_PORT" 2>/dev/null; then
        log_success "SSH port $SSH_PORT is accessible"
        return 0
    else
        log_info "SSH port $SSH_PORT not yet accessible (VM may be booting)"
        return 0  # Not a failure - VM might still be booting
    fi
}

# Check if HTTP port is accessible
check_http_port() {
    if nc -zv localhost "$HTTP_PORT" 2>/dev/null; then
        log_success "HTTP port $HTTP_PORT is accessible"
        return 0
    else
        log_info "HTTP port $HTTP_PORT not yet accessible"
        return 0  # Not a failure - service may not be running
    fi
}

# Main health check logic
main() {
    local exit_code=$EXIT_SUCCESS

    # Critical check: QEMU must be running
    if ! check_qemu_process; then
        exit_code=$EXIT_FAILURE
    fi

    # Informational checks (don't fail if not ready)
    check_ssh_port || true
    check_http_port || true

    # Exit with appropriate code
    if [ $exit_code -eq $EXIT_SUCCESS ]; then
        log_success "Container is healthy"
    else
        log_error "Container is unhealthy"
    fi

    exit $exit_code
}

# Run main function
main "$@"
