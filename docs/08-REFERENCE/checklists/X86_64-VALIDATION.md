# x86_64-Only Validation Checklist for Debian GNU/Hurd QEMU-in-Docker

## Overview
This checklist verifies that the Docker container and QEMU setup are running in pure x86_64 mode with ZERO i386 contamination.

## Pre-Build Validation

### 1. Host System Check
```bash
# Verify host is x86_64
uname -m
# Expected: x86_64

# Check Docker architecture
docker version --format '{{.Server.Arch}}'
# Expected: amd64
```

### 2. Dockerfile Validation
```bash
# Check for i386 references (should return nothing)
grep -i "i386\|i686\|ia32" Dockerfile

# Verify x86_64 binary path
grep "qemu-system-x86_64" Dockerfile
# Should show: /usr/bin/qemu-system-x86_64
```

## Build-Time Validation

### 3. Build the Container
```bash
# Build with verification
docker-compose build --no-cache

# During build, watch for:
# - "Architecture verified: x86_64-only configuration"
# - "ERROR: i386 packages detected" (should NOT appear)
```

### 4. Inspect Built Image
```bash
# Check image architecture
docker inspect ghcr.io/oichkatzelesfrettschen/gnu-hurd-x86_64:latest \
  | jq '.[0].Architecture'
# Expected: "amd64"

# Verify QEMU binary in image
docker run --rm ghcr.io/oichkatzelesfrettschen/gnu-hurd-x86_64:latest \
  ls -la /usr/bin/qemu-system-x86_64
# Should show executable file
```

## Runtime Validation

### 5. Start Container
```bash
# Start with KVM if available
docker-compose up -d

# Check container logs for architecture verification
docker-compose logs hurd-x86_64 | grep -E "Architecture|x86_64|i386"
# Should show: "Architecture verified: x86_64-only configuration"
# Should NOT show any i386 references
```

### 6. Verify QEMU Process
```bash
# Check running QEMU process inside container
docker exec hurd-x86_64-qemu ps aux | grep qemu

# Should show:
# - /usr/bin/qemu-system-x86_64 (with underscore!)
# - NOT qemu-system-i386
```

### 7. Check Package Architecture
```bash
# List all packages in container
docker exec hurd-x86_64-qemu dpkg --get-selections | grep -E ":i386|i386-"
# Should return NOTHING (no i386 packages)

# Verify QEMU package
docker exec hurd-x86_64-qemu dpkg -l qemu-system-x86
# Should show amd64 architecture
```

### 8. KVM/TCG Detection
```bash
# Check acceleration mode
docker-compose logs hurd-x86_64 | grep -E "KVM|TCG"

# With KVM available:
# - "KVM hardware acceleration detected and will be used"
# - "CPU model: host"

# Without KVM:
# - "KVM not available, using TCG software emulation"
# - "CPU model: max"
```

### 9. QEMU Configuration Verification
```bash
# Connect to QEMU monitor
telnet localhost 9999

# In monitor, run:
(qemu) info version
# Should show QEMU version for x86_64

(qemu) info cpus
# Should show x86_64 CPU architecture

(qemu) info kvm
# Should show "kvm support: enabled" if KVM available

(qemu) quit
```

### 10. Guest Architecture Check
```bash
# SSH into Hurd VM (once booted)
ssh -p 2222 root@localhost

# Inside Hurd VM:
uname -m
# Expected: x86_64

dpkg --print-architecture
# Expected: amd64

# Check for i386 packages
dpkg --get-selections | grep i386
# Should return NOTHING
```

## Performance Validation

### 11. Check CPU Features
```bash
# In QEMU monitor
(qemu) info registers
# Should show 64-bit registers (RAX, RBX, etc., not EAX, EBX)

# With KVM:
(qemu) info kvm
# Should show: "kvm support: enabled"

# Check CPU model
(qemu) info cpu-model-expansion type=static model=host
# Should show host CPU features if KVM enabled
```

### 12. Memory Check
```bash
# Verify 64-bit memory addressing
docker exec hurd-x86_64-qemu cat /proc/meminfo | grep MemTotal
# Can allocate more than 4GB (not limited to 32-bit addressing)
```

## Network and Device Validation

### 13. Network Device
```bash
# In QEMU monitor
(qemu) info network
# Should show: e1000 NIC (NOT virtio - Hurd doesn't support well)
```

### 14. Storage Device
```bash
# In QEMU monitor
(qemu) info block
# Should show: IDE interface (NOT virtio-blk)
```

## Common Issues and Solutions

### Issue: Container shows i386 packages
**Solution**: Rebuild with `docker-compose build --no-cache`

### Issue: QEMU binary not found
**Solution**: Verify path is `/usr/bin/qemu-system-x86_64` (with underscore!)

### Issue: KVM not working
**Solution**: Run with `--device=/dev/kvm` or check permissions

### Issue: Guest shows i386 architecture
**Solution**: Download correct x86_64/amd64 Hurd image from:
- https://cdimage.debian.org/cdimage/ports/13.0/hurd-amd64/

## Automated Validation Script

Save as `validate-x86_64.sh`:

```bash
#!/bin/bash

echo "=== x86_64-Only Validation Script ==="

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

# Function to run test
run_test() {
    local test_name="$1"
    local test_cmd="$2"
    local expected="$3"

    echo -n "Testing: $test_name... "
    result=$(eval "$test_cmd" 2>&1)

    if echo "$result" | grep -q "$expected"; then
        echo -e "${GREEN}PASS${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}FAIL${NC}"
        echo "  Expected: $expected"
        echo "  Got: $result"
        ((TESTS_FAILED++))
    fi
}

# Run tests
run_test "Host architecture" "uname -m" "x86_64"
run_test "Docker architecture" "docker version --format '{{.Server.Arch}}'" "amd64"
run_test "No i386 in Dockerfile" "grep -c 'i386' Dockerfile" "^0$"
run_test "QEMU x86_64 binary specified" "grep -c 'qemu-system-x86_64' Dockerfile" "[1-9]"
run_test "Container running" "docker ps --filter name=hurd-x86_64-qemu -q | wc -l" "^1$"

# If container is running, do additional checks
if docker ps --filter name=hurd-x86_64-qemu -q | grep -q .; then
    run_test "QEMU process is x86_64" \
        "docker exec hurd-x86_64-qemu pgrep -f 'qemu-system-x86_64' | wc -l" \
        "^1$"

    run_test "No i386 packages in container" \
        "docker exec hurd-x86_64-qemu sh -c 'dpkg --get-selections | grep -c i386'" \
        "^0$"
fi

# Summary
echo ""
echo "=== Summary ==="
echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed! System is x86_64-only.${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed. Please review the configuration.${NC}"
    exit 1
fi
```

## Final Verification

After all checks pass:

1. ✅ No i386 packages in container
2. ✅ QEMU binary is `/usr/bin/qemu-system-x86_64`
3. ✅ Guest VM runs as x86_64/amd64
4. ✅ KVM acceleration works when available
5. ✅ TCG fallback works when KVM unavailable
6. ✅ IDE disk and e1000 NIC for Hurd compatibility
7. ✅ Port forwarding works (SSH on 2222, HTTP on 8080)
8. ✅ No virtio devices (Hurd doesn't support well)

## Success Criteria

The system is considered pure x86_64 when:

- **ZERO** i386 packages or binaries exist
- **ALL** processes run in 64-bit mode
- **QEMU** uses x86_64 binary exclusively
- **Guest** VM reports x86_64/amd64 architecture
- **Performance** benefits from KVM when available
- **Compatibility** maintained with Hurd requirements (IDE, e1000)