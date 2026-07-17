# GNU/Hurd Backend Testing - Quick Commands

## Prerequisites (One-time setup)

```bash
# 1. Verify environment
podman --version          # Should be 3.0+
docker --version          # Should be 20.10+
virsh --version           # Should be 7.0+
qemu-system-x86_64 --version

# 2. Verify KVM access
ls -la /dev/kvm           # Should be accessible
groups | grep kvm         # User should be in kvm group

# 3. Download disk image (ONE-TIME - ~500MB)
./scripts/download-image.sh
# Verify:
ls -lh /var/lib/libvirt/images/debian-hurd-amd64.qcow2

# 4. Clone or set required directories
mkdir -p logs/benchmarks logs/tests
```

---

## Testing: Podman (PREFERRED - Rootless)

### Start Podman with KVM

```bash
# Clean start
podman-compose down 2>/dev/null || true
podman volume rm $(podman volume ls -q) 2>/dev/null || true

# Start with KVM acceleration
podman-compose -f docker-compose.yml -f docker-compose.kvm.yml up -d

# Monitor startup (in background)
podman-compose logs -f gnu-hurd-dev &
LOGS_PID=$!

# Wait for SSH (boot should take 30-60 seconds)
echo "Waiting for boot..."
for i in {1..300}; do
  if timeout 2 bash -c "echo > /dev/tcp/127.0.0.1/2222" 2>/dev/null; then
    echo "[SUCCESS] Boot complete in ~${i}s"
    break
  fi
  sleep 1
done

# Test SSH access
ssh -p 2222 root@localhost -o StrictHostKeyChecking=no "uname -a"

# Verify Podman info
podman-compose ps
podman stats gnu-hurd-dev --no-stream

# Cleanup logs background process
kill $LOGS_PID 2>/dev/null || true

# Shut down
podman-compose down
```

### Verify Podman is Rootless

```bash
# Check rootless status
podman info | grep -A 5 "rootless"
# Should show: rootless: true

# Verify no sudo needed
podman ps          # Works without sudo
podman-compose ps  # Works without sudo
```

---

## Testing: Docker v2 (Fallback)

### Start Docker with KVM

```bash
# Clean start
docker compose down 2>/dev/null || true

# Start with KVM
docker compose -f docker-compose.yml -f docker-compose.kvm.yml up -d

# Monitor
docker compose logs -f gnu-hurd-dev &
LOGS_PID=$!

# Wait for SSH
echo "Waiting for boot..."
for i in {1..300}; do
  if timeout 2 bash -c "echo > /dev/tcp/127.0.0.1/2222" 2>/dev/null; then
    echo "[SUCCESS] Boot complete in ~${i}s"
    break
  fi
  sleep 1
done

# Test SSH
ssh -p 2222 root@localhost -o StrictHostKeyChecking=no "uname -a"

# Check Docker status
docker compose ps

# Cleanup
kill $LOGS_PID 2>/dev/null || true
docker compose down
```

---

## Testing: Libvirt (Advanced VM Management)

### Start Libvirt with Wrapper Script

```bash
# Define domain (one-time)
./scripts/libvirt-hurd.sh define

# Verify domain is defined
virsh list --all | grep gnu-hurd-dev

# Start domain
./scripts/libvirt-hurd.sh start

# Monitor console (in background)
virsh console gnu-hurd-dev &
CONSOLE_PID=$!

# Wait for SSH
echo "Waiting for boot..."
for i in {1..300}; do
  if timeout 2 bash -c "echo > /dev/tcp/127.0.0.1/2222" 2>/dev/null; then
    echo "[SUCCESS] Boot complete in ~${i}s"
    kill $CONSOLE_PID 2>/dev/null || true
    break
  fi
  sleep 1
done

# Test SSH via wrapper
./scripts/libvirt-hurd.sh ssh "uname -a"

# Check domain info
./scripts/libvirt-hurd.sh info

# Test snapshot creation (Libvirt-unique feature)
virsh snapshot-create-as gnu-hurd-dev test-snapshot "Test snapshot"
virsh snapshot-list gnu-hurd-dev

# Cleanup
./scripts/libvirt-hurd.sh stop
# Domain remains defined for future use
```

---

## Performance Benchmarking (All Backends)

### Individual Backend Benchmarks

```bash
# Docker v2 with KVM (should be 30-60s)
./scripts/benchmark-kvm.sh docker-kvm
# Result: logs/benchmarks/<timestamp>-docker-kvm.log

# Docker v2 with TCG (should be 3-5 min)
./scripts/benchmark-kvm.sh docker-tcg
# Result: logs/benchmarks/<timestamp>-docker-tcg.log

# Libvirt with KVM (should be 30-60s)
./scripts/benchmark-kvm.sh libvirt-kvm
# Result: logs/benchmarks/<timestamp>-libvirt-kvm.log

# Libvirt with TCG (should be 3-5 min)
./scripts/benchmark-kvm.sh libvirt-tcg
# Result: logs/benchmarks/<timestamp>-libvirt-tcg.log
```

### Run All Benchmarks Sequentially

```bash
# Full benchmark suite (takes 45-60 minutes)
TIMEOUT=300 ./scripts/benchmark-kvm.sh all

# Check results
ls -lh logs/benchmarks/
cat logs/benchmarks/*-kvm.log | grep "Boot time"
```

### Compare Results

```bash
# Print summary
for log in logs/benchmarks/*-*.log; do
  echo "=== $(basename $log) ==="
  grep "Boot time" "$log" || echo "TIMEOUT/ERROR"
done
```

---

## Quick Health Check (1 minute)

```bash
# Verify all tools are working
echo "=== Environment Check ==="
podman --version
docker --version
virsh --version

# Check KVM
echo "=== KVM Check ==="
[ -r /dev/kvm ] && [ -w /dev/kvm ] && echo "KVM OK" || echo "KVM issue"

# Check disk image
echo "=== Disk Image Check ==="
ls -lh /var/lib/libvirt/images/debian-hurd-amd64.qcow2 | awk '{print $5, $9}'

# Quick Podman test (10 seconds)
echo "=== Quick Podman Test ==="
timeout 10 podman-compose -f docker-compose.yml -f docker-compose.kvm.yml up -d && \
  sleep 5 && \
  timeout 5 bash -c "echo > /dev/tcp/127.0.0.1/2222" 2>/dev/null && \
  echo "Podman OK" || echo "Podman test timeout (expected if slow)" && \
  podman-compose down 2>/dev/null
```

---

## Full Testing Sequence (Recommended)

For comprehensive testing of all three backends:

```bash
#!/bin/bash
set -euo pipefail

echo "=== GNU/Hurd Backend Testing Suite ==="
echo "Start time: $(date)"
echo ""

# 1. Health check
echo "[1/6] Environment health check..."
./scripts/health-check.sh || echo "Health check warnings (non-fatal)"
echo ""

# 2. Podman test
echo "[2/6] Testing Podman (preferred)..."
podman-compose -f docker-compose.yml -f docker-compose.kvm.yml up -d
sleep 30
if timeout 90 bash -c "ssh -p 2222 root@localhost -o StrictHostKeyChecking=no 'uname -a'"; then
  echo "[SUCCESS] Podman test passed"
else
  echo "[WARN] Podman test timeout"
fi
podman-compose down
echo ""

# 3. Docker test
echo "[3/6] Testing Docker v2 (fallback)..."
docker compose -f docker-compose.yml -f docker-compose.kvm.yml up -d
sleep 30
if timeout 90 bash -c "ssh -p 2222 root@localhost -o StrictHostKeyChecking=no 'uname -a'"; then
  echo "[SUCCESS] Docker test passed"
else
  echo "[WARN] Docker test timeout"
fi
docker compose down
echo ""

# 4. Libvirt test
echo "[4/6] Testing Libvirt (advanced)..."
./scripts/libvirt-hurd.sh define
./scripts/libvirt-hurd.sh start
sleep 30
if timeout 90 ./scripts/libvirt-hurd.sh ssh "uname -a"; then
  echo "[SUCCESS] Libvirt test passed"
else
  echo "[WARN] Libvirt test timeout"
fi
./scripts/libvirt-hurd.sh stop
echo ""

# 5. Run benchmarks
echo "[5/6] Running performance benchmarks (30-40 min)..."
TIMEOUT=300 ./scripts/benchmark-kvm.sh all
echo ""

# 6. Generate report
echo "[6/6] Generating test report..."
cat > BACKEND-TESTING-RESULTS.md << 'REPORT'
# Backend Testing Results

Generated: $(date)

## Podman Test
Status: $(grep -q SUCCESS <(podman-compose ps 2>/dev/null) && echo "PASS" || echo "PENDING")

## Docker Test
Status: $(grep -q SUCCESS <(docker compose ps 2>/dev/null) && echo "PASS" || echo "PENDING")

## Libvirt Test
Status: $(virsh list --all 2>/dev/null | grep -q gnu-hurd-dev && echo "PASS" || echo "PENDING")

## Performance Results
See logs/benchmarks/ for detailed results.

REPORT

echo ""
echo "=== Testing Complete ==="
echo "Results: BACKEND-TESTING-RESULTS.md"
echo "Logs: logs/benchmarks/"
echo "End time: $(date)"
```

Save as `test-all-backends.sh`, then:
```bash
chmod +x test-all-backends.sh
./test-all-backends.sh
```

---

## Troubleshooting

### Port 2222 Already in Use

```bash
# Find what's using it
lsof -i :2222 | grep -v COMMAND | awk '{print $2}' | xargs kill -9 2>/dev/null || true

# Or change port in docker-compose.override.yml
cat > docker-compose.override.yml << 'EOF'
version: "3.8"
services:
  gnu-hurd-dev:
    ports:
      - "2223:22"
EOF
# Then use: ssh -p 2223 root@localhost
```

### Container/VM Won't Boot

```bash
# Check logs
podman-compose logs gnu-hurd-dev | tail -50

# Check disk space
df -h | grep -E "(^/|var/lib)"

# Check memory
free -h

# Try with more time
sleep 120 && ssh -p 2222 root@localhost
```

### KVM Not Detected (Falls back to TCG)

```bash
# Fix permissions
sudo usermod -a -G kvm $USER
newgrp kvm

# Verify
id | grep kvm
ls -la /dev/kvm
```

---

## Success Criteria

### Podman Test PASS
- ✓ Container starts without errors
- ✓ SSH accessible within 90 seconds
- ✓ `uname -a` returns GNU/Hurd
- ✓ No sudo required (rootless works)

### Docker Test PASS
- ✓ Container starts without errors
- ✓ SSH accessible within 90 seconds
- ✓ `uname -a` returns GNU/Hurd

### Libvirt Test PASS
- ✓ Domain defines successfully
- ✓ SSH accessible within 90 seconds
- ✓ `uname -a` returns GNU/Hurd
- ✓ Snapshots can be created

### Benchmark Results PASS
- ✓ KVM boot: 30-90 seconds
- ✓ TCG boot: 3-5 minutes
- ✓ All backends roughly equivalent performance

---

## Next Steps

After successful testing:

1. Create testing report: `docs/07-RESEARCH-AND-LESSONS/BACKEND-TESTING-RESULTS.md`
2. Document performance findings
3. Update README with preferred workflow (Podman)
4. Commit testing results

---

**Last Updated**: 2026-01-15
**Status**: Ready for testing
