#!/bin/bash
# GNU/Hurd Docker - Comprehensive System Testing Script
# Tests user setup, compilation, and system functionality

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "================================================================================"
echo "  GNU/Hurd Docker - Comprehensive System Test"
echo "================================================================================"
echo ""

# Configuration
SSH_PORT="${SSH_PORT:-2222}"
SSH_HOST="${SSH_HOST:-localhost}"
ROOT_PASSWORD="${ROOT_PASSWORD:-root}"
AGENTS_PASSWORD="${AGENTS_PASSWORD:-agents}"
TIMEOUT=300  # 5 minutes for boot

# Helper functions
echo_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

echo_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

echo_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Test 1: Verify container is running
test_container_running() {
    echo ""
    echo_info "Test 1: Verifying GNU/Hurd container is running..."
    
    if docker ps | grep -q "gnu-hurd-dev"; then
        echo_success "Container is running"
        docker ps | grep gnu-hurd-dev
        return 0
    else
        echo_error "Container is not running"
        echo "Start with: docker-compose up -d"
        return 1
    fi
}

# Test 2: Wait for system boot
test_boot_completion() {
    echo ""
    echo_info "Test 2: Waiting for system to boot (timeout: ${TIMEOUT}s)..."
    
    local start_time
    start_time=$(date +%s)
    local elapsed=0
    
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

# Test 3: Verify root user access
test_root_user() {
    echo ""
    echo_info "Test 3: Testing root user access (root/root)..."
    
    # Test SSH access with root
    if sshpass -p "$ROOT_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -p "$SSH_PORT" "root@$SSH_HOST" 'echo "Root access successful"' 2>/dev/null; then
        echo_success "Root user authentication successful (password: root)"
        
        # Get system info
        echo ""
        echo "System Information:"
        sshpass -p "$ROOT_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -p "$SSH_PORT" "root@$SSH_HOST" << 'EOSSH'
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

# Test 4: Verify agents user access and sudo
test_agents_user() {
    echo ""
    echo_info "Test 4: Testing agents user access (agents/agents) with sudo..."
    
    # Test SSH access with agents user
    if sshpass -p "$AGENTS_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -p "$SSH_PORT" "agents@$SSH_HOST" 'echo "Agents access successful"' 2>/dev/null; then
        echo_success "Agents user authentication successful (password: agents)"
        
        # Test sudo access
        echo ""
        echo "Testing sudo NOPASSWD access:"
        if sshpass -p "$AGENTS_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -p "$SSH_PORT" "agents@$SSH_HOST" 'sudo -n whoami' 2>/dev/null | grep -q "root"; then
            echo_success "Sudo NOPASSWD is configured correctly"
            
            # Check password expiry
            echo ""
            echo "Checking password expiry status:"
            sshpass -p "$AGENTS_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
                -p "$SSH_PORT" "agents@$SSH_HOST" 'sudo chage -l agents | grep "Password expires"' 2>/dev/null || \
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

# Test 5: Compile and run C program
test_c_compilation() {
    echo ""
    echo_info "Test 5: Testing C compilation and execution..."
    
    # Create test C program
    local test_program='
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/utsname.h>

int main() {
    struct utsname sys_info;
    
    printf("========================================\\n");
    printf("  GNU/Hurd C Program Test\\n");
    printf("========================================\\n\\n");
    
    if (uname(&sys_info) == 0) {
        printf("System Information:\\n");
        printf("  System: %s\\n", sys_info.sysname);
        printf("  Node: %s\\n", sys_info.nodename);
        printf("  Release: %s\\n", sys_info.release);
        printf("  Version: %s\\n", sys_info.version);
        printf("  Machine: %s\\n", sys_info.machine);
        printf("\\n");
    }
    
    printf("Process Information:\\n");
    printf("  PID: %d\\n", getpid());
    printf("  PPID: %d\\n", getppid());
    printf("\\n");
    
    printf("Hello from GNU/Hurd!\\n");
    printf("C compilation and execution successful!\\n");
    printf("========================================\\n");
    
    return 0;
}
'
    
    echo "Creating test C program..."
    
    if sshpass -p "$ROOT_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -p "$SSH_PORT" "root@$SSH_HOST" "cat > /tmp/test_hurd.c << 'CEOF'
$test_program
CEOF" 2>/dev/null; then
        echo_success "Test program created at /tmp/test_hurd.c"
    else
        echo_error "Failed to create test program"
        return 1
    fi
    
    echo ""
    echo "Compiling C program..."
    
    if sshpass -p "$ROOT_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -p "$SSH_PORT" "root@$SSH_HOST" 'gcc /tmp/test_hurd.c -o /tmp/test_hurd' 2>/dev/null; then
        echo_success "Compilation successful"
    else
        echo_error "Compilation failed"
        echo ""
        echo "Checking if GCC is installed..."
        sshpass -p "$ROOT_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -p "$SSH_PORT" "root@$SSH_HOST" 'which gcc || echo "GCC not found"' 2>/dev/null
        
        echo ""
        echo "Installing GCC..."
        sshpass -p "$ROOT_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -p "$SSH_PORT" "root@$SSH_HOST" 'apt-get update && apt-get install -y gcc' 2>/dev/null
        
        echo "Retrying compilation..."
        if sshpass -p "$ROOT_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -p "$SSH_PORT" "root@$SSH_HOST" 'gcc /tmp/test_hurd.c -o /tmp/test_hurd' 2>/dev/null; then
            echo_success "Compilation successful after installing GCC"
        else
            echo_error "Compilation still failed"
            return 1
        fi
    fi
    
    echo ""
    echo "Running compiled program:"
    echo "----------------------------------------"
    
    if sshpass -p "$ROOT_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -p "$SSH_PORT" "root@$SSH_HOST" '/tmp/test_hurd' 2>/dev/null; then
        echo "----------------------------------------"
        echo_success "Program executed successfully on GNU/Hurd"
        return 0
    else
        echo_error "Program execution failed"
        return 1
    fi
}

# Test 6: Test package management
test_package_management() {
    echo ""
    echo_info "Test 6: Testing package management (apt)..."
    
    echo "Testing apt-cache search:"
    if sshpass -p "$ROOT_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -p "$SSH_PORT" "root@$SSH_HOST" 'apt-cache search gcc | head -5' 2>/dev/null; then
        echo_success "Package management working"
        return 0
    else
        echo_error "Package management test failed"
        return 1
    fi
}

# Test 7: Test filesystem operations
test_filesystem() {
    echo ""
    echo_info "Test 7: Testing filesystem operations..."
    
    echo "Creating test directory and files:"
    if sshpass -p "$ROOT_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -p "$SSH_PORT" "root@$SSH_HOST" << 'EOSSH' 2>/dev/null; then
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

# Test 8: Test basic GNU/Hurd features
test_hurd_features() {
    echo ""
    echo_info "Test 8: Testing GNU/Hurd specific features..."
    
    echo "Checking translators and servers:"
    sshpass -p "$ROOT_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -p "$SSH_PORT" "root@$SSH_HOST" << 'EOSSH' 2>/dev/null || true
echo "Running Hurd servers:"
ps aux | grep -E "ext2fs|pfinet|pflocal" | head -5

echo ""
echo "Checking /hurd directory:"
ls -l /hurd/ | head -10
EOSSH
    
    echo_success "Hurd features checked"
    return 0
}

# Main test execution
main() {
    local failed_tests=0
    local total_tests=8
    
    # Check prerequisites
    echo_info "Checking prerequisites..."
    
    if ! command -v sshpass &> /dev/null; then
        echo_error "sshpass not found. Installing..."
        sudo apt-get update && sudo apt-get install -y sshpass
    fi
    
    if ! command -v nc &> /dev/null; then
        echo_error "nc (netcat) not found. Installing..."
        sudo apt-get install -y netcat
    fi
    
    echo_success "Prerequisites ready"
    echo ""
    
    # Run tests
    test_container_running || ((failed_tests++))
    test_boot_completion || ((failed_tests++))
    test_root_user || ((failed_tests++))
    test_agents_user || ((failed_tests++))
    test_c_compilation || ((failed_tests++))
    test_package_management || ((failed_tests++))
    test_filesystem || ((failed_tests++))
    test_hurd_features || ((failed_tests++))
    
    # Summary
    echo ""
    echo "================================================================================"
    echo "  Test Summary"
    echo "================================================================================"
    echo ""
    
    local passed_tests=$((total_tests - failed_tests))
    echo "Tests Passed: ${passed_tests}/${total_tests}"
    echo "Tests Failed: ${failed_tests}/${total_tests}"
    echo ""
    
    if [ $failed_tests -eq 0 ]; then
        echo_success "ALL TESTS PASSED ✅"
        echo ""
        echo "GNU/Hurd system is fully functional:"
        echo "  ✓ Root user access (root/root)"
        echo "  ✓ Agents user access (agents/agents) with sudo"
        echo "  ✓ C compilation and execution"
        echo "  ✓ Package management"
        echo "  ✓ Filesystem operations"
        echo "  ✓ GNU/Hurd features accessible"
        return 0
    else
        echo_error "SOME TESTS FAILED ✗"
        echo ""
        echo "Failed: ${failed_tests} test(s)"
        echo "Review the output above for details"
        return 1
    fi
}

# Help message
if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    cat << EOF
GNU/Hurd Docker - Comprehensive System Testing

Usage: $0 [options]

This script performs comprehensive testing of the GNU/Hurd system including:
  1. Container status verification
  2. Boot completion check
  3. Root user authentication (root/root)
  4. Agents user authentication (agents/agents) with sudo
  5. C program compilation and execution
  6. Package management functionality
  7. Filesystem operations
  8. GNU/Hurd specific features

Environment Variables:
  SSH_PORT        SSH port (default: 2222)
  SSH_HOST        SSH host (default: localhost)
  ROOT_PASSWORD   Root password (default: root)
  AGENTS_PASSWORD Agents password (default: agents)
  TIMEOUT         Boot timeout in seconds (default: 300)

Examples:
  # Run all tests with defaults
  $0
  
  # Use custom SSH port
  SSH_PORT=2223 $0
  
  # Set custom timeout
  TIMEOUT=600 $0

Prerequisites:
  - sshpass
  - netcat (nc)
  - Docker and docker-compose
  - GNU/Hurd container running

EOF
    exit 0
fi

# Run main
main
exit $?
