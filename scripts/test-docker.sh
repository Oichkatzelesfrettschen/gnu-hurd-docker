#!/bin/bash
set -euo pipefail

# GNU/Hurd Docker - Testing Script
# Tests Docker setup and container functionality

echo "=========================================="
echo "GNU/Hurd Docker - Test Suite"
echo "=========================================="
echo ""

PASS=0
FAIL=0

# Helper functions
pass() {
    echo "[PASS] $1"
    PASS=$((PASS + 1))
}

fail() {
    echo "[FAIL] $1"
    FAIL=$((FAIL + 1))
}

# Test 1: Docker installation
echo "Test 1: Docker installation..."
if command -v docker &> /dev/null; then
    pass "Docker installed"
else
    fail "Docker not installed"
    exit 1
fi

# Test 2: Docker daemon running
echo "Test 2: Docker daemon running..."
if docker ps > /dev/null 2>&1; then
    pass "Docker daemon running"
else
    fail "Docker daemon not running"
fi

# Test 3: Docker Compose installed
echo "Test 3: Docker Compose installed..."
if docker compose version &> /dev/null; then
    pass "Docker Compose installed"
else
    fail "Docker Compose not installed"
fi

# Test 4: Configuration files exist
echo "Test 4: Configuration files..."
[ -f "Dockerfile" ] && pass "Dockerfile exists" || fail "Dockerfile missing"
[ -f "entrypoint.sh" ] && pass "entrypoint.sh exists" || fail "entrypoint.sh missing"
[ -f "docker-compose.yml" ] && pass "docker-compose.yml exists" || fail "docker-compose.yml missing"

# Test 5: QCOW2 image exists
echo "Test 5: QCOW2 image..."
if [ -f "debian-hurd-amd64.qcow2" ]; then
    SIZE=$(du -h "debian-hurd-amd64.qcow2" | cut -f1)
    pass "QCOW2 image found ($SIZE)"
else
    fail "QCOW2 image not found (run ./scripts/download-image.sh)"
fi

# Test 6: Docker build dry-run
echo "Test 6: Docker build validation..."
if docker build --dry-run . > /dev/null 2>&1; then
    pass "Docker build dry-run successful"
else
    fail "Docker build dry-run failed"
fi

# Test 7: Available disk space
echo "Test 7: Disk space..."
AVAILABLE=$(df -m . | tail -1 | awk '{print $4}')
if [ "$AVAILABLE" -gt 4096 ]; then
    pass "Sufficient disk space ($AVAILABLE MB)"
else
    fail "Insufficient disk space ($AVAILABLE MB, need 4+ GB)"
fi

# Test 8: Available memory
echo "Test 8: Available RAM..."
AVAILABLE_RAM=$(free -m | grep Mem | awk '{print $7}')
if [ "$AVAILABLE_RAM" -gt 2048 ]; then
    pass "Sufficient available RAM ($AVAILABLE_RAM MB)"
else
    fail "Low available RAM ($AVAILABLE_RAM MB, recommend 2+ GB)"
fi

# Summary
echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo ""

if [ $FAIL -eq 0 ]; then
    echo "All tests passed! Ready to deploy."
    echo ""
    echo "Next steps:"
    echo "  docker compose build"
    echo "  docker compose up -d"
    echo "  docker compose logs -f"
    exit 0
else
    echo "Some tests failed. Please review errors above."
    exit 1
fi
