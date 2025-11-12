#!/usr/bin/env bash
# test-phases/06-filesystem.sh - Filesystem Operations Tests
# WHY: Verify basic filesystem operations work correctly
# WHAT: Test directory creation, file I/O, and cleanup
# HOW: Create test directory with files, verify, then clean up

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=test-phases/common.sh
. "$SCRIPT_DIR/common.sh"

# Test: Filesystem operations
test_filesystem() {
    echo ""
    echo_info "Phase 6: Testing filesystem operations..."
    
    echo "Creating test directory and files:"
    if ssh_root_heredoc << 'EOSSH'; then
mkdir -p /tmp/hurd_test
cd /tmp/hurd_test
echo "Test file 1" > file1.txt
echo "Test file 2" > file2.txt
ls -la
cat file1.txt file2.txt
rm -rf /tmp/hurd_test
echo "Cleanup complete"
EOSSH
        echo_success "Filesystem operations working"
        return 0
    else
        echo_error "Filesystem operations failed"
        return 1
    fi
}

# Run test if executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ] || [ "$0" = "sh" ] || [ "$0" = "bash" ]; then
    test_filesystem
    exit $?
fi
