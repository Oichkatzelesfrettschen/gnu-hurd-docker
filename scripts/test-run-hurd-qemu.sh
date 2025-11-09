#!/bin/bash
# =============================================================================
# Test Script for run-hurd-qemu.sh
# =============================================================================
# PURPOSE:
# - Validate run-hurd-qemu.sh without actually launching QEMU
# - Test command building, argument parsing, and auto-detection
# =============================================================================

set -euo pipefail

readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0

test_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((TESTS_PASSED++))
}

test_fail() {
    echo -e "${RED}✗${NC} $1"
    ((TESTS_FAILED++))
}

test_info() {
    echo -e "${YELLOW}ℹ${NC} $1"
}

echo "=================================================================="
echo "  Testing run-hurd-qemu.sh"
echo "=================================================================="
echo ""

# Test 1: Script exists and is executable
echo "[Test 1] Script file checks..."
if [[ -f "scripts/run-hurd-qemu.sh" ]]; then
    test_pass "Script file exists"
else
    test_fail "Script file not found"
fi

if [[ -x "scripts/run-hurd-qemu.sh" ]]; then
    test_pass "Script is executable"
else
    test_fail "Script is not executable"
fi

# Test 2: Help text works
echo ""
echo "[Test 2] Help text..."
if ./scripts/run-hurd-qemu.sh --help >/dev/null 2>&1; then
    test_pass "Help text displays without errors"
else
    test_fail "Help text failed"
fi

# Test 3: ShellCheck validation
echo ""
echo "[Test 3] ShellCheck validation..."
if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck scripts/run-hurd-qemu.sh; then
        test_pass "ShellCheck validation passed"
    else
        test_fail "ShellCheck validation failed"
    fi
else
    test_info "ShellCheck not installed (skipping)"
fi

# Test 4: Image auto-detection
echo ""
echo "[Test 4] Image auto-detection..."
if [[ -f "images/debian-hurd-amd64.qcow2" ]]; then
    test_pass "QCOW2 image found in images/"
    qemu-img info images/debian-hurd-amd64.qcow2 2>&1 | grep "virtual size" | sed 's/^/  /'
else
    test_fail "QCOW2 image not found (needed for testing)"
fi

# Test 5: QEMU availability
echo ""
echo "[Test 5] QEMU availability..."
if command -v qemu-system-x86_64 >/dev/null 2>&1; then
    test_pass "qemu-system-x86_64 found in PATH"
    qemu-system-x86_64 --version | head -1 | sed 's/^/  /'
else
    test_fail "qemu-system-x86_64 not found"
fi

# Test 6: KVM detection
echo ""
echo "[Test 6] KVM availability..."
if [[ -e /dev/kvm ]]; then
    if [[ -r /dev/kvm ]] && [[ -w /dev/kvm ]]; then
        test_pass "KVM device accessible (/dev/kvm)"
        ls -l /dev/kvm | sed 's/^/  /'
    else
        test_info "KVM device exists but not accessible (permissions issue)"
    fi
else
    test_info "KVM device not found (TCG mode will be used)"
fi

# Test 7: Command-line argument parsing (dry run simulation)
echo ""
echo "[Test 7] Argument parsing validation..."

# Create a minimal test by checking if the script accepts valid arguments
if ./scripts/run-hurd-qemu.sh --help >/dev/null 2>&1; then
    test_pass "Script accepts --help argument"
fi

# Test invalid argument handling
if ./scripts/run-hurd-qemu.sh --invalid-option 2>&1 | grep -q "Unknown option"; then
    test_pass "Script correctly rejects invalid arguments"
else
    test_fail "Script did not reject invalid arguments"
fi

# Test 8: Required dependencies
echo ""
echo "[Test 8] Dependencies check..."
MISSING_DEPS=0

for cmd in qemu-system-x86_64 qemu-img; do
    if command -v "$cmd" >/dev/null 2>&1; then
        test_pass "$cmd available"
    else
        test_fail "$cmd not found"
        ((MISSING_DEPS++))
    fi
done

# Summary
echo ""
echo "=================================================================="
echo "  Test Summary"
echo "=================================================================="
echo ""
echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $TESTS_FAILED"

if [[ $MISSING_DEPS -gt 0 ]]; then
    echo ""
    test_info "Missing dependencies: Install with 'sudo pacman -S qemu-base'"
fi

echo ""
if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}All tests passed!${NC} ✓"
    echo ""
    echo "Next steps:"
    echo "  1. Launch VM: ./scripts/run-hurd-qemu.sh"
    echo "  2. Connect: ssh -p 2222 root@localhost"
    echo "  3. Serial: telnet localhost 5555"
    exit 0
else
    echo -e "${RED}Some tests failed.${NC}"
    echo "Please fix issues before using the script."
    exit 1
fi
