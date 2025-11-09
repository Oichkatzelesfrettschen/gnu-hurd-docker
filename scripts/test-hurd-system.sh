#!/bin/sh
# GNU/Hurd Docker - Comprehensive System Testing Script
# WHY: Orchestrate modular test phases for maintainability
# WHAT: Main test runner that executes all test phases in order
# HOW: Source phase modules and track results
# CLEANUP: Track test artifacts and SSH sessions for cleanup on error

set -euo pipefail

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Source color library
# shellcheck source=lib/colors.sh
. "$SCRIPT_DIR/lib/colors.sh"

# Track cleanup state
CLEANUP_NEEDED=false
SSH_SESSIONS=""

cleanup() {
    local exit_code=$?
    
    if [ "$CLEANUP_NEEDED" = true ]; then
        echo ""
        echo_info "Cleaning up test artifacts..."
        
        # Kill any background SSH processes from tests
        if [ -n "$SSH_SESSIONS" ]; then
            # Use pgrep to find and kill processes by pattern if available
            if command -v pgrep >/dev/null 2>&1; then
                pgrep -f "ssh.*$SSH_HOST.*$SSH_PORT" | while read -r pid; do
                    kill "$pid" 2>/dev/null || true
                    echo_info "  Terminated SSH process: PID $pid"
                done
            fi
        fi
    fi
    
    exit $exit_code
}

trap cleanup EXIT INT TERM

# Configuration
export SSH_PORT="${SSH_PORT:-2222}"
export SSH_HOST="${SSH_HOST:-localhost}"
export ROOT_PASSWORD="${ROOT_PASSWORD:-root}"
export AGENTS_PASSWORD="${AGENTS_PASSWORD:-agents}"
export TIMEOUT="${TIMEOUT:-300}"

# Help message
if [ $# -gt 0 ] && { [ "$1" = "--help" ] || [ "$1" = "-h" ]; }; then
    cat << EOF
GNU/Hurd Docker - Comprehensive System Testing

Usage: $0 [options]

Tests: Container, Boot, Users, Compilation, Packages, Filesystem, Hurd Features

Environment Variables:
  SSH_PORT=${SSH_PORT}  SSH_HOST=${SSH_HOST}  TIMEOUT=${TIMEOUT}
  ROOT_PASSWORD=${ROOT_PASSWORD}  AGENTS_PASSWORD=${AGENTS_PASSWORD}

Prerequisites: sshpass, netcat, docker compose

EOF
    exit 0
fi

echo "================================================================================"
echo "  GNU/Hurd Docker - Comprehensive System Test"
echo "================================================================================"
echo ""

# Check prerequisites
check_prerequisites() {
    echo_info "Checking prerequisites..."
    local missing=0
    
    command -v sshpass >/dev/null 2>&1 || { echo_error "sshpass not found"; missing=1; }
    command -v nc >/dev/null 2>&1 || { echo_error "nc not found"; missing=1; }
    
    [ $missing -eq 0 ] && echo_success "Prerequisites ready"
    return $missing
}

# Run all test phases
run_tests() {
    local failed=0
    local phases="01-infrastructure 02-boot 03-users 04-compilation 05-packages 06-filesystem 07-hurd-features"
    
    for phase in $phases; do
        local script="$SCRIPT_DIR/test-phases/${phase}.sh"
        [ ! -f "$script" ] && { echo_error "Missing: $phase"; failed=$((failed + 1)); continue; }
        
        # shellcheck source=/dev/null
        . "$script"
        
        # Get test function name and run it
        local func
        func=$(grep -E '^test_[a-z_]+\(\)' "$script" | head -1 | sed 's/().*//')
        [ -n "$func" ] && $func || failed=$((failed + 1))
    done
    
    echo "$failed:7"
}

# Print summary
print_summary() {
    local failed total passed
    failed=$(echo "$1" | cut -d: -f1)
    total=$(echo "$1" | cut -d: -f2)
    passed=$((total - failed))
    
    echo ""
    echo "================================================================================"
    echo "  Test Summary"
    echo "================================================================================"
    echo ""
    echo "Tests Passed: ${passed}/${total}"
    echo "Tests Failed: ${failed}/${total}"
    echo ""
    
    if [ "$failed" -eq 0 ]; then
        echo_success "ALL TESTS PASSED"
        echo ""
        echo "GNU/Hurd system is fully functional:"
        echo "  * Root and agents user access with sudo"
        echo "  * C compilation and execution"
        echo "  * Package management and filesystem"
        echo "  * GNU/Hurd features accessible"
        return 0
    else
        echo_error "SOME TESTS FAILED"
        echo "Failed: ${failed} test(s) - Review output above"
        return 1
    fi
}

# Main execution
main() {
    check_prerequisites || exit 1
    echo ""
    print_summary "$(run_tests)"
}

main
exit $?
