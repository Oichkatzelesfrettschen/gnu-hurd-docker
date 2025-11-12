#!/usr/bin/env bash
# test-phases/03-users.sh - User Account Validation
# WHY: Verify both root and agents users are properly configured
# WHAT: Test SSH access and sudo permissions for both accounts
# HOW: Use SSH authentication and sudo tests

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=test-phases/common.sh
. "$SCRIPT_DIR/common.sh"

# Test: Verify root user access
test_root_user() {
    echo ""
    echo_info "Testing root user access (root/root)..."
    
    if ssh_root 'echo "Root access successful"'; then
        echo_success "Root user authentication successful (password: root)"
        
        echo ""
        echo "System Information:"
        ssh_root_heredoc << 'EOSSH'
echo "  Hostname: $(hostname)"
echo "  Kernel: $(uname -s)"
echo "  Kernel Version: $(uname -r)"
echo "  Architecture: $(uname -m)"
echo "  OS Info: $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')"
EOSSH
        return 0
    else
        echo_error "Root user authentication failed"
        return 1
    fi
}

# Test: Verify agents user access and sudo
test_agents_user() {
    echo ""
    echo_info "Testing agents user access (agents/agents) with sudo..."
    
    if ssh_agents 'echo "Agents access successful"'; then
        echo_success "Agents user authentication successful (password: agents)"
        
        echo ""
        echo "Testing sudo NOPASSWD access:"
        if ssh_agents 'sudo -n whoami' | grep -q "root"; then
            echo_success "Sudo NOPASSWD is configured correctly"
            
            echo ""
            echo "Checking password expiry status:"
            ssh_agents 'sudo chage -l agents | grep "Password expires"' || \
                echo "  Password expiry: Not forced to change on first login"
            
            return 0
        else
            echo_warning "Sudo requires password (NOPASSWD not configured)"
            return 1
        fi
    else
        echo_error "Agents user authentication failed"
        return 1
    fi
}

# Test: Combined user validation
test_users() {
    echo ""
    echo_info "Phase 3: Validating user accounts..."
    
    local result=0
    test_root_user || result=1
    test_agents_user || result=1
    
    return $result
}

# Run test if executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ] || [ "$0" = "sh" ] || [ "$0" = "bash" ]; then
    test_users
    exit $?
fi
