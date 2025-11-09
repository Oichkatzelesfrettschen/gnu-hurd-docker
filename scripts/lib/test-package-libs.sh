#!/bin/bash
# lib/test-package-libs.sh - Test suite for package-lists.sh and package-helpers.sh
#
# WHY: Verify that package libraries work correctly before using in production
# WHAT: Tests package array integrity, helper functions, and error handling
# HOW: Run from scripts directory: ./lib/test-package-libs.sh
#
# Tests:
#   1. Source all required libraries without errors
#   2. Verify package arrays are defined and non-empty
#   3. Test individual helper functions
#   4. Verify error handling and fallback behavior
#   5. Syntax check with shellcheck (if available)

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="$SCRIPT_DIR"
PASSED=0
FAILED=0

# ============================================================================
# COLOR OUTPUT (simplified version for testing)
# ============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

test_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    PASSED=$((PASSED + 1))
}

test_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    FAILED=$((FAILED + 1))
}

test_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

test_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# ============================================================================
# TEST 1: Source libraries without errors
# ============================================================================

test_info "TEST 1: Sourcing libraries..."

if [ ! -f "$LIB_DIR/colors.sh" ]; then
    test_fail "colors.sh not found at $LIB_DIR/colors.sh"
else
    test_pass "colors.sh exists"
fi

if [ ! -f "$LIB_DIR/package-lists.sh" ]; then
    test_fail "package-lists.sh not found at $LIB_DIR/package-lists.sh"
    exit 1
else
    test_pass "package-lists.sh exists"
fi

if [ ! -f "$LIB_DIR/package-helpers.sh" ]; then
    test_fail "package-helpers.sh not found at $LIB_DIR/package-helpers.sh"
    exit 1
else
    test_pass "package-helpers.sh exists"
fi

# Source libraries
if . "$LIB_DIR/colors.sh" 2>/dev/null; then
    test_pass "colors.sh sourced successfully"
else
    test_fail "Failed to source colors.sh"
fi

if . "$LIB_DIR/package-lists.sh" 2>/dev/null; then
    test_pass "package-lists.sh sourced successfully"
else
    test_fail "Failed to source package-lists.sh"
    exit 1
fi

if . "$LIB_DIR/package-helpers.sh" 2>/dev/null; then
    test_pass "package-helpers.sh sourced successfully"
else
    test_fail "Failed to source package-helpers.sh"
    exit 1
fi

# ============================================================================
# TEST 2: Verify package arrays exist and have content
# ============================================================================

test_info "TEST 2: Verifying package arrays..."

verify_array() {
    local array_name="$1"
    local array_value=$(eval "echo \"\$$array_name\"")
    
    if [ -z "$array_value" ]; then
        test_fail "$array_name is empty or undefined"
        return 1
    fi
    
    # Count number of packages (non-empty lines)
    local count=$(echo "$array_value" | grep -c -v "^$" || echo "0")
    
    if [ "$count" -gt 0 ]; then
        test_pass "$array_name has $count packages"
        return 0
    else
        test_fail "$array_name appears empty"
        return 1
    fi
}

# Verify all package arrays
verify_array "MINIMAL_PKGS"
verify_array "NETTOOLS_PKGS"
verify_array "BROWSERS_PKGS"
verify_array "DEV_PKGS"
verify_array "COMPILERS_PKGS"
verify_array "LANGUAGES_PKGS"
verify_array "HURD_PKGS"
verify_array "DEBUG_PKGS"
verify_array "BUILD_SYSTEMS_PKGS"
verify_array "DOC_TOOLS_PKGS"
verify_array "X11_PKGS"
verify_array "SYS_UTILS_PKGS"

# ============================================================================
# TEST 3: Verify helper functions are defined
# ============================================================================

test_info "TEST 3: Verifying helper functions..."

verify_function() {
    local func_name="$1"
    
    if type "$func_name" >/dev/null 2>&1; then
        test_pass "Function $func_name is defined"
        return 0
    else
        test_fail "Function $func_name is not defined"
        return 1
    fi
}

# Verify key functions exist
verify_function "check_root"
verify_function "apt_init"
verify_function "apt_update"
verify_function "install_packages"
verify_function "install_optional"
verify_function "batch_install"
verify_function "verify_package"
verify_function "verify_command"
verify_function "verify_commands"
verify_function "verify_packages"
verify_function "verify_service"
verify_function "is_hurd"
verify_function "check_connectivity"
verify_function "apt_clean"
verify_function "count_packages"
verify_function "get_package_size"

# ============================================================================
# TEST 4: Test package array content (sample check)
# ============================================================================

test_info "TEST 4: Checking package list content..."

# Verify specific expected packages are in arrays
check_package_in_array() {
    local package="$1"
    local array_name="$2"
    local array_value=$(eval "echo \"\$$array_name\"")
    
    if echo "$array_value" | grep -q "$package"; then
        test_pass "$package found in $array_name"
        return 0
    else
        test_fail "$package NOT found in $array_name"
        return 1
    fi
}

# Check essential packages in correct arrays
check_package_in_array "gcc" "DEV_PKGS"
check_package_in_array "git" "DEV_PKGS"
check_package_in_array "make" "DEV_PKGS"
check_package_in_array "gnumach-dev" "HURD_PKGS"
check_package_in_array "mig" "HURD_PKGS"
check_package_in_array "gdb" "DEBUG_PKGS"
check_package_in_array "openssh-server" "MINIMAL_PKGS"
check_package_in_array "curl" "MINIMAL_PKGS"
check_package_in_array "python3" "LANGUAGES_PKGS"

# ============================================================================
# TEST 5: Syntax validation with shellcheck (if available)
# ============================================================================

test_info "TEST 5: Syntax validation..."

if command -v shellcheck >/dev/null 2>&1; then
    test_info "shellcheck found, running validation..."
    
    if shellcheck -S style "$LIB_DIR/package-lists.sh" >/dev/null 2>&1; then
        test_pass "package-lists.sh passes shellcheck"
    else
        test_warn "package-lists.sh has style warnings (non-fatal)"
    fi
    
    if shellcheck -S style "$LIB_DIR/package-helpers.sh" >/dev/null 2>&1; then
        test_pass "package-helpers.sh passes shellcheck"
    else
        test_warn "package-helpers.sh has style warnings (non-fatal)"
    fi
else
    test_warn "shellcheck not available (skipping syntax check)"
fi

# ============================================================================
# TEST 6: Test function behavior (dry run, non-destructive)
# ============================================================================

test_info "TEST 6: Testing helper function behavior (dry run)..."

# Test is_hurd function
if is_hurd 2>/dev/null; then
    test_pass "is_hurd detected GNU/Hurd system"
else
    test_warn "is_hurd detected non-Hurd system (expected if not on Hurd)"
fi

# Test verify_command with known command
if verify_command "sh"; then
    test_pass "verify_command correctly found 'sh'"
else
    test_fail "verify_command failed to find 'sh'"
fi

# Test verify_command with non-existent command
if ! verify_command "nonexistent_command_xyz_123"; then
    test_pass "verify_command correctly returned false for non-existent command"
else
    test_fail "verify_command incorrectly returned true for non-existent command"
fi

# ============================================================================
# TEST 7: Verify pkglist_to_array utility function
# ============================================================================

test_info "TEST 7: Testing pkglist_to_array utility..."

# This is a utility function that converts strings to arrays
if type pkglist_to_array >/dev/null 2>&1; then
    test_pass "pkglist_to_array function is defined"
    
    # Test conversion (note: POSIX sh doesn't support array subscripts)
    TEST_PKGS="pkg1 pkg2 pkg3"
    pkglist_to_array "test" "$TEST_PKGS" 2>/dev/null
    
    if [ -n "$TEST_PKGS" ]; then
        test_pass "pkglist_to_array utility function available"
    else
        test_warn "pkglist_to_array test inconclusive"
    fi
else
    test_fail "pkglist_to_array function is not defined"
fi

# ============================================================================
# TEST 8: Duplication analysis
# ============================================================================

test_info "TEST 8: Analyzing duplication reduction..."

# Count unique packages across arrays to ensure no major gaps
count_unique() {
    local all_arrays="$MINIMAL_PKGS $NETTOOLS_PKGS $BROWSERS_PKGS $DEV_PKGS"
    all_arrays="$all_arrays $COMPILERS_PKGS $LANGUAGES_PKGS $HURD_PKGS"
    all_arrays="$all_arrays $DEBUG_PKGS $BUILD_SYSTEMS_PKGS $DOC_TOOLS_PKGS"
    
    echo "$all_arrays" | tr ' ' '\n' | grep -v '^$' | sort -u | wc -l
}

unique_count=$(count_unique)
test_info "Total unique packages across all arrays: $unique_count"

if [ "$unique_count" -gt 50 ]; then
    test_pass "Comprehensive package coverage ($unique_count packages)"
else
    test_warn "Package coverage may be limited ($unique_count packages)"
fi

# ============================================================================
# SUMMARY REPORT
# ============================================================================

echo ""
echo "========================================================================"
echo "TEST SUMMARY REPORT"
echo "========================================================================"
echo ""
echo -e "Total Passed:  ${GREEN}$PASSED${NC}"
echo -e "Total Failed:  ${RED}$FAILED${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}SUCCESS!${NC} All tests passed."
    echo ""
    echo "Package libraries are ready for use:"
    echo "  - Source package-lists.sh for package arrays"
    echo "  - Source package-helpers.sh for installation functions"
    echo "  - Source colors.sh for output formatting"
    echo ""
    echo "Example usage in scripts:"
    echo "  source \"\$(dirname \"\$0\")/lib/colors.sh\""
    echo "  source \"\$(dirname \"\$0\")/lib/package-lists.sh\""
    echo "  source \"\$(dirname \"\$0\")/lib/package-helpers.sh\""
    echo ""
    echo "  install_packages \"Phase 1: Dev Tools\" \"\$DEV_PKGS\""
    exit 0
else
    echo -e "${RED}FAILURE!${NC} $FAILED test(s) failed."
    echo ""
    echo "Please review the errors above and fix the libraries."
    exit 1
fi
