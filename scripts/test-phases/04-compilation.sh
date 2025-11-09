#!/bin/sh
# test-phases/04-compilation.sh - C Compilation Tests
# WHY: Verify GCC toolchain and compilation capabilities
# WHAT: Compile and execute a C program that uses system calls
# HOW: Create test program, compile with gcc, execute and verify output

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=test-phases/common.sh
. "$SCRIPT_DIR/common.sh"

# Test: Compile and run C program
test_compilation() {
    echo ""
    echo_info "Phase 4: Testing C compilation and execution..."
    
    # Create test C program
    echo "Creating test C program..."
    ssh_root 'cat > /tmp/test_hurd.c << '\''EOF'\''
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/utsname.h>

int main() {
    struct utsname sys_info;
    printf("GNU/Hurd C Test\n");
    if (uname(&sys_info) == 0) {
        printf("System: %s\n", sys_info.sysname);
        printf("Release: %s\n", sys_info.release);
    }
    printf("PID: %d\n", getpid());
    printf("Hello from GNU/Hurd!\n");
    return 0;
}
EOF'
    
    echo_success "Test program created"
    
    # Compile the program
    echo ""
    echo "Compiling C program..."
    if ssh_root 'gcc /tmp/test_hurd.c -o /tmp/test_hurd 2>&1'; then
        echo_success "Compilation successful"
    else
        echo_warning "Compilation failed, checking for GCC..."
        if ! remote_command_exists root gcc; then
            echo "Installing GCC..."
            ssh_root 'apt-get update && apt-get install -y gcc' || true
            echo "Retrying compilation..."
            if ssh_root 'gcc /tmp/test_hurd.c -o /tmp/test_hurd 2>&1'; then
                echo_success "Compilation successful after installing GCC"
            else
                echo_error "Compilation still failed"
                return 1
            fi
        else
            echo_error "GCC exists but compilation failed"
            return 1
        fi
    fi
    
    # Run the compiled program
    echo ""
    echo "Running compiled program:"
    echo "----------------------------------------"
    if ssh_root '/tmp/test_hurd'; then
        echo "----------------------------------------"
        echo_success "Program executed successfully on GNU/Hurd"
        return 0
    else
        echo_error "Program execution failed"
        return 1
    fi
}

# Run test if executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ] || [ "$0" = "sh" ] || [ "$0" = "bash" ]; then
    test_compilation
    exit $?
fi
