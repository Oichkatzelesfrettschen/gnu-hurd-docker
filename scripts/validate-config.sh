#!/bin/bash
set -euo pipefail

# GNU/Hurd Docker - Configuration Validation Script
# Validates Dockerfile, entrypoint.sh, and docker-compose.yml

echo "=========================================="
echo "GNU/Hurd Docker Configuration Validator"
echo "=========================================="
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ERRORS=0
WARNINGS=0

# Helper functions
pass() {
    echo -e "${GREEN}[OK]${NC} $1"
}

fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ERRORS=$((ERRORS + 1))
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    WARNINGS=$((WARNINGS + 1))
}

# Check if files exist
echo "1. Checking file existence..."
echo ""

if [ -f "Dockerfile" ]; then
    pass "Dockerfile found"
else
    fail "Dockerfile not found"
    exit 1
fi

if [ -f "entrypoint.sh" ]; then
    pass "entrypoint.sh found"
else
    fail "entrypoint.sh not found"
    exit 1
fi

if [ -f "docker-compose.yml" ]; then
    pass "docker-compose.yml found"
else
    fail "docker-compose.yml not found"
    exit 1
fi

echo ""

# Validate Dockerfile
echo "2. Validating Dockerfile..."
echo ""

if docker build --dry-run . > /dev/null 2>&1; then
    pass "Dockerfile syntax valid"
else
    fail "Dockerfile has syntax errors"
fi

# Check key directives
if grep -q "^FROM debian:bookworm" Dockerfile; then
    pass "Base image is debian:bookworm"
else
    warn "Base image is not debian:bookworm"
fi

if grep -q "qemu-system-x86-64" Dockerfile; then
    pass "QEMU package included"
else
    fail "QEMU package not found in Dockerfile"
fi

if grep -q "ENTRYPOINT" Dockerfile; then
    pass "ENTRYPOINT defined"
else
    warn "ENTRYPOINT not defined"
fi

echo ""

# Validate entrypoint.sh
echo "3. Validating entrypoint.sh..."
echo ""

if command -v shellcheck &> /dev/null; then
    if shellcheck -S error entrypoint.sh > /dev/null 2>&1; then
        pass "entrypoint.sh passes shellcheck"
    else
        fail "entrypoint.sh has shellcheck errors:"
        shellcheck -S error entrypoint.sh | head -10
    fi
else
    warn "shellcheck not installed - skipping shell validation"
fi

if grep -q "^#!/bin/bash" entrypoint.sh; then
    pass "Proper shebang present"
else
    fail "Missing or incorrect shebang"
fi

if grep -q "set -e" entrypoint.sh; then
    pass "Error handling (set -e) enabled"
else
    warn "Missing error handling (set -e)"
fi

if grep -q "qemu-system-x86_64" entrypoint.sh; then
    pass "QEMU launcher found"
else
    fail "QEMU launcher not found"
fi

echo ""

# Validate docker-compose.yml
echo "4. Validating docker-compose.yml..."
echo ""

if command -v python3 &> /dev/null; then
    if python3 -c "import yaml; yaml.safe_load(open('docker-compose.yml'))" > /dev/null 2>&1; then
        pass "docker-compose.yml valid YAML"
    else
        fail "docker-compose.yml has YAML syntax errors"
    fi
else
    warn "python3 not installed - skipping YAML validation"
fi

if grep -q "version:" docker-compose.yml; then
    pass "Version field present"
else
    warn "Missing version field"
fi

if grep -q "services:" docker-compose.yml; then
    pass "Services section present"
else
    fail "Missing services section"
fi

if grep -q "gnu-hurd-dev:" docker-compose.yml; then
    pass "gnu-hurd-dev service defined"
else
    fail "gnu-hurd-dev service not defined"
fi

if grep -q "privileged: true" docker-compose.yml; then
    pass "Privileged mode enabled"
else
    warn "Privileged mode not enabled (required for QEMU)"
fi

if grep -q "volumes:" docker-compose.yml; then
    pass "Volumes configured"
else
    warn "No volumes configured"
fi

if grep -q "ports:" docker-compose.yml; then
    pass "Port mappings configured"
else
    warn "No port mappings configured"
fi

echo ""

# Check disk image
echo "5. Checking disk image..."
echo ""

if [ -f "debian-hurd-i386-20250807.qcow2" ]; then
    SIZE=$(du -h "debian-hurd-i386-20250807.qcow2" | cut -f1)
    pass "QCOW2 image found (size: $SIZE)"
    
    if command -v file &> /dev/null; then
        if file "debian-hurd-i386-20250807.qcow2" | grep -q "QEMU"; then
            pass "QCOW2 format verified"
        else
            fail "File is not a valid QCOW2 image"
        fi
    fi
else
    warn "QCOW2 image not found (expected for production deployment)"
    echo "    Run: ./scripts/download-image.sh"
fi

echo ""

# Summary
echo "=========================================="
echo "Validation Summary"
echo "=========================================="
echo -e "Errors:   ${RED}$ERRORS${NC}"
echo -e "Warnings: ${YELLOW}$WARNINGS${NC}"
echo ""

if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}Configuration is VALID${NC}"
    exit 0
else
    echo -e "${RED}Configuration has ERRORS${NC}"
    exit 1
fi
