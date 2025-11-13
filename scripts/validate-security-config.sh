#!/bin/bash
# =============================================================================
# validate-security-config.sh - Validate docker-compose.yml security configuration
# =============================================================================
# PURPOSE:
#   Validates that docker-compose.yml matches security promises in SECURITY.md
#   Ensures security-critical configuration options are properly set
#
# USAGE:
#   ./scripts/validate-security-config.sh [docker-compose.yml]
#
# EXIT CODES:
#   0 - All security checks passed
#   1 - One or more security checks failed
# =============================================================================

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
COMPOSE_FILE="${1:-docker-compose.yml}"
ERRORS=0

# Helper functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
    ((ERRORS++))
}

check_file_exists() {
    if [[ ! -f "$COMPOSE_FILE" ]]; then
        log_error "File not found: $COMPOSE_FILE"
        exit 1
    fi
    log_info "Validating: $COMPOSE_FILE"
}

# Security checks
check_no_new_privileges() {
    log_info "Checking: no-new-privileges security option..."
    if grep -q "no-new-privileges:true" "$COMPOSE_FILE"; then
        log_info "  ✓ no-new-privileges:true is configured"
    else
        log_error "  ✗ no-new-privileges:true is NOT configured (SECURITY.md Section 4.4)"
    fi
}

check_cap_drop_all() {
    log_info "Checking: capability drop configuration..."
    if grep -q "cap_drop:" "$COMPOSE_FILE" && grep -A1 "cap_drop:" "$COMPOSE_FILE" | grep -q "ALL"; then
        log_info "  ✓ cap_drop: [ALL] is configured"
    else
        log_error "  ✗ cap_drop: [ALL] is NOT configured (SECURITY.md Section 4.4)"
    fi
}

check_localhost_binding() {
    log_info "Checking: localhost port binding (recommended)..."
    
    # Check if any ports are bound to 0.0.0.0 explicitly
    if grep -E '^\s*-\s+"0\.0\.0\.0:' "$COMPOSE_FILE" >/dev/null 2>&1; then
        log_warn "  ⚠ Ports are bound to 0.0.0.0 (all interfaces)"
        log_warn "    For production, bind to localhost: 127.0.0.1:PORT:PORT"
    else
        # Check for explicit localhost binding or default (no IP prefix)
        if grep -E '^\s*-\s+"127\.0\.0\.1:' "$COMPOSE_FILE" >/dev/null 2>&1; then
            log_info "  ✓ Ports are explicitly bound to localhost (127.0.0.1)"
        elif grep -E '^\s*-\s+"[0-9]+:[0-9]+"' "$COMPOSE_FILE" >/dev/null 2>&1; then
            log_info "  ✓ Ports use default binding (localhost for development)"
        else
            log_info "  ℹ No port bindings found or non-standard format"
        fi
    fi
}

check_privileged_mode() {
    log_info "Checking: privileged mode (should be false)..."
    if grep -q "privileged: false" "$COMPOSE_FILE"; then
        log_info "  ✓ privileged: false is configured"
    elif grep -q "privileged: true" "$COMPOSE_FILE"; then
        log_error "  ✗ privileged: true is enabled (should be false per SECURITY.md)"
    else
        log_warn "  ⚠ privileged mode not explicitly set (defaults to false)"
    fi
}

check_secrets_configured() {
    log_info "Checking: Docker secrets configuration..."
    if grep -q "^secrets:" "$COMPOSE_FILE"; then
        log_info "  ✓ Secrets section is configured"
    else
        log_warn "  ⚠ Secrets section not found (recommended in SECURITY.md Section 4.1)"
    fi
}

check_security_opt() {
    log_info "Checking: security_opt configuration..."
    if grep -q "security_opt:" "$COMPOSE_FILE"; then
        log_info "  ✓ security_opt section is present"
    else
        log_error "  ✗ security_opt section is missing (SECURITY.md Section 4.4)"
    fi
}

check_resource_limits() {
    log_info "Checking: resource limits..."
    local has_limits=false
    
    if grep -q "mem_limit:" "$COMPOSE_FILE"; then
        log_info "  ✓ mem_limit is configured"
        has_limits=true
    fi
    
    if grep -q "cpus:" "$COMPOSE_FILE"; then
        log_info "  ✓ cpus limit is configured"
        has_limits=true
    fi
    
    if grep -q "pids_limit:" "$COMPOSE_FILE"; then
        log_info "  ✓ pids_limit is configured"
        has_limits=true
    fi
    
    if [[ "$has_limits" == false ]]; then
        log_warn "  ⚠ No resource limits configured (recommended for production)"
    fi
}

# Main validation
main() {
    echo "======================================"
    echo "Security Configuration Validator"
    echo "======================================"
    echo ""
    
    check_file_exists
    echo ""
    
    # Run all security checks
    check_no_new_privileges
    echo ""
    check_cap_drop_all
    echo ""
    check_localhost_binding
    echo ""
    check_privileged_mode
    echo ""
    check_secrets_configured
    echo ""
    check_security_opt
    echo ""
    check_resource_limits
    echo ""
    
    # Summary
    echo "======================================"
    if [[ $ERRORS -eq 0 ]]; then
        log_info "All security checks passed! ✓"
        echo "======================================"
        exit 0
    else
        log_error "Security validation failed with $ERRORS error(s)"
        echo "======================================"
        echo ""
        echo "Please review SECURITY.md and update $COMPOSE_FILE accordingly."
        exit 1
    fi
}

# Run main function
main "$@"
