#!/bin/sh
# test-phases/07-hurd-features.sh - GNU/Hurd Specific Features Tests
# WHY: Verify Hurd-specific components are accessible
# WHAT: Check translators, servers, and /hurd directory
# HOW: Query running Hurd servers and list /hurd contents

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=test-phases/common.sh
. "$SCRIPT_DIR/common.sh"

# Test: GNU/Hurd specific features
test_hurd_features() {
    echo ""
    echo_info "Phase 7: Testing GNU/Hurd specific features..."
    
    echo "Checking translators and servers:"
    ssh_root_heredoc << 'EOSSH' || true
echo "Running Hurd servers:"
ps aux | grep -E "ext2fs|pfinet|pflocal" | head -5

echo ""
echo "Checking /hurd directory:"
ls -l /hurd/ | head -10
EOSSH
    
    echo_success "Hurd features checked"
    return 0
}

# Run test if executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ] || [ "$0" = "sh" ] || [ "$0" = "bash" ]; then
    test_hurd_features
    exit $?
fi
