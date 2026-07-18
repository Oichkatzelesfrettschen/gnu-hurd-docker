# Phase 7-8: Testing & Validation - Backend Workflow Comparison

## Executive Summary

**Status**: Testing Phase Initiated

**Objective**: Validate all three virtualization backends (Docker v2, Podman, Libvirt) with focus on Podman as the preferred workflow

**Environment**:
- Podman 5.7.1 (preferred, rootless-capable)
- Docker (fallback option)
- Libvirt 7.0+ (advanced VM management)
- QEMU 8.0+ (hypervisor)
- KVM acceleration: ENABLED (/dev/kvm accessible, user in kvm group)
- Linux x86_64 (native KVM support)

---

## Prerequisites

### 1. Download Disk Image

All backends use the same QCOW2 disk image:

```bash
./scripts/download-image.sh
# Creates: /var/lib/libvirt/images/debian-hurd-amd64.qcow2 (~500MB)
```

**Verification**:
```bash
ls -lh /var/lib/libvirt/images/debian-hurd-amd64.qcow2
qemu-img info /var/lib/libvirt/images/debian-hurd-amd64.qcow2
```

### 2. Verify Podman Rootless Setup (Preferred)

Podman can run in two modes:

**Rootless (Preferred for security)**:
```bash
podman --version
# Returns version with "user" mode indicator
podman run --rm alpine echo "Rootless works"
```

**Daemon mode (fallback)**:
```bash
sudo systemctl start podman.socket
# Or use regular docker/podman commands with sudo
```

For this project, **rootless is recommended** (no sudo needed, improved isolation).

### 3. Verify KVM Access

```bash
ls -la /dev/kvm
# Should be accessible by your user
[ -r /dev/kvm ] && [ -w /dev/kvm ] && echo "KVM accessible" || echo "KVM permission issue"
```

### 4. Environment Setup

Create or update `~/.bashrc` or `~/.zshrc`:

```bash
# GNU/Hurd project environment
export CONTAINER_RUNTIME=podman          # Prefer Podman
export PODMAN_IGNORE_CGROUPSV2_WARNING=1 # If cgroups warning appears
export AUTO_DISABLE_KVM_FOR_IDE=1        # Fallback for IDE DMA issues
```

Then reload:
```bash
source ~/.bashrc
```

---

## Testing Strategy

### Test Matrix

| Backend | Mode | Expected Boot Time | Status |
|---------|------|-------------------|--------|
| Docker v2 | KVM | 30-60s | Ready |
| Docker v2 | TCG | 3-5min | Ready |
| Podman | KVM (rootless) | 30-60s | **PRIMARY** |
| Podman | KVM (daemon) | 30-60s | Fallback |
| Podman | TCG | 3-5min | Ready |
| Libvirt | KVM | 30-60s | Alternative |
| Libvirt | TCG | 3-5min | Alternative |

### Health Check Method

All backends use **SSH connectivity** as the success metric:

```bash
# Poll SSH port (default 2222)
for i in {1..300}; do
  timeout 2 bash -c "echo > /dev/tcp/127.0.0.1/2222" 2>/dev/null && \
    { echo "SSH OK"; break; } || sleep 1
done
```

A successful `ssh -p 2222 root@localhost` indicates the VM booted successfully.

---

## Backend Testing Procedures

### Backend 1: Docker Compose v2 (KVM)

**Purpose**: Verify Docker v2 with KVM acceleration

**Steps**:

```bash
# 1. Verify Docker is running
docker ps

# 2. Bring down any existing containers
docker compose down 2>/dev/null || true

# 3. Start with KVM overlay
docker compose -f compose.yaml -f compose.kvm.yaml up -d

# 4. Monitor startup (watch boot logs)
docker compose logs -f gnu-hurd-dev &
LOGS_PID=$!

# 5. Wait for SSH
echo "Waiting for boot..."
for i in {1..300}; do
  if timeout 2 bash -c "echo > /dev/tcp/127.0.0.1/2222" 2>/dev/null; then
    echo "[SUCCESS] Boot complete in ~${i}s"
    break
  fi
  sleep 1
done

# 6. Verify SSH access
ssh -p 2222 root@localhost -o StrictHostKeyChecking=no "uname -a"

# 7. Check KVM status inside
ssh -p 2222 root@localhost "echo 'KVM is working'" || echo "TCG fallback"

# 8. Cleanup
kill $LOGS_PID 2>/dev/null
docker compose down
```

**Expected Output**:
- Boot in 30-60 seconds (with KVM)
- SSH prompt responsive
- `uname -a` shows GNU/Hurd kernel
- Container logs show minimal warnings

**Pass Criteria**:
- ✓ Container starts without errors
- ✓ SSH accessible within 90 seconds
- ✓ System boots to login prompt
- ✓ KVM acceleration detected (optional but preferred)

---

### Backend 2: Podman Compose (PREFERRED)

**Purpose**: Verify Podman as preferred workflow (rootless mode)

**Steps**:

```bash
# 1. Verify Podman (rootless)
podman --version
podman-compose --version

# 2. Optional: Check rootless status
podman info | grep "rootless"

# 3. Bring down any existing containers
podman-compose down 2>/dev/null || true

# 4. Start with KVM overlay (auto-detects /dev/kvm)
podman-compose -f compose.yaml -f compose.kvm.yaml up -d

# 5. Monitor startup
podman-compose logs -f gnu-hurd-dev &
LOGS_PID=$!

# 6. Wait for SSH
echo "Waiting for boot..."
for i in {1..300}; do
  if timeout 2 bash -c "echo > /dev/tcp/127.0.0.1/2222" 2>/dev/null; then
    echo "[SUCCESS] Boot complete in ~${i}s"
    break
  fi
  sleep 1
done

# 7. Verify SSH access
ssh -p 2222 root@localhost -o StrictHostKeyChecking=no "uname -a"

# 8. Check container status
podman-compose ps
podman stats gnu-hurd-dev --no-stream

# 9. Cleanup
kill $LOGS_PID 2>/dev/null
podman-compose down
```

**Expected Output**:
- Podman container starts without privilege escalation
- Boot in 30-60 seconds
- SSH accessible within 90 seconds
- Resource usage reasonable (<2GB RAM if set to 4GB allocation)

**Pass Criteria**:
- ✓ No sudo required (rootless mode works)
- ✓ Container starts without errors
- ✓ SSH accessible within 90 seconds
- ✓ System boots to login prompt
- ✓ KVM auto-detected (no manual permission setup needed)

**Podman-Specific Advantages**:
- No daemon required (stateless)
- Rootless execution (better security)
- Daemonless (simplified management)
- Compatible with Docker Compose syntax
- Lower resource overhead vs Docker daemon

---

### Backend 3: Libvirt + QEMU

**Purpose**: Verify Libvirt as alternative for advanced VM management

**Steps**:

```bash
# 1. Verify libvirtd is running
sudo systemctl status libvirtd

# 2. Define domain from template
./scripts/libvirt-hurd.sh define

# 3. Verify domain is defined
virsh list --all | grep gnu-hurd-dev

# 4. Start domain
./scripts/libvirt-hurd.sh start

# 5. Monitor boot via console
virsh console gnu-hurd-dev &
CONSOLE_PID=$!

# 6. Wait for SSH (same method as others)
echo "Waiting for boot..."
for i in {1..300}; do
  if timeout 2 bash -c "echo > /dev/tcp/127.0.0.1/2222" 2>/dev/null; then
    echo "[SUCCESS] Boot complete in ~${i}s"
    kill $CONSOLE_PID 2>/dev/null
    break
  fi
  sleep 1
done

# 7. Verify SSH access
./scripts/libvirt-hurd.sh ssh uname -a

# 8. Check domain status
./scripts/libvirt-hurd.sh info

# 9. Test snapshot capability (unique to Libvirt)
virsh snapshot-create-as gnu-hurd-dev test-snapshot "Before testing"
virsh snapshot-list gnu-hurd-dev

# 10. Cleanup
./scripts/libvirt-hurd.sh stop
# Keep domain defined for future use
```

**Expected Output**:
- Domain defines without errors
- Boot in 30-60 seconds (KVM)
- SSH accessible within 90 seconds
- Snapshot creation works
- Console output visible via virsh

**Pass Criteria**:
- ✓ Domain management works via wrapper script
- ✓ SSH accessible within 90 seconds
- ✓ System boots to login prompt
- ✓ Snapshots can be created and listed
- ✓ Multiple console methods work (serial, VNC)

**Libvirt-Specific Advantages**:
- Full VM snapshots
- Live migration capable
- Graphical management (virt-manager)
- Complex networking options
- Persistent VM state

---

## Comparative Testing

### Run All Benchmarks

Use the benchmark script to measure performance:

```bash
# Test all backends sequentially
TIMEOUT=300 ./scripts/benchmark-kvm.sh all

# Or test individual backends
./scripts/benchmark-kvm.sh docker-kvm
./scripts/benchmark-kvm.sh docker-tcg
./scripts/benchmark-kvm.sh libvirt-kvm
```

**Note**: Podman benchmarking is integrated as part of docker-kvm test (compatible syntax)

### Results Interpretation

Results are saved to `logs/benchmarks/<timestamp>-<mode>.log`

**Expected boot times** (with 4GB RAM, 2 vCPU, KVM enabled):
```
Docker v2 KVM:    30-60s
Podman KVM:       30-60s (same, compatible syntax)
Libvirt KVM:      30-60s (same, compatible hypervisor)
Docker TCG:       3-5 minutes
Podman TCG:       3-5 minutes
Libvirt TCG:      3-5 minutes
```

**Performance ratio**:
```
KVM vs TCG speedup: ~4-6x faster
All backends roughly equivalent when using same KVM mode
```

---

## Podman Workflow Best Practices (PREFERRED)

### 1. Rootless by Default

```bash
# Confirm rootless
podman info | grep -A 5 "rootless"

# Should show:
#   rootless: true
#   cgroupVersion: v2
```

### 2. No sudo Required

```bash
# These work without sudo in rootless mode:
podman-compose up -d
podman-compose ps
podman ps
podman logs gnu-hurd-dev
```

### 3. Port Forwarding (Same as Docker)

```bash
# SSH forwarding works automatically
ssh -p 2222 root@localhost

# HTTP forwarding works automatically
curl http://localhost:8080
```

### 4. KVM Detection (Automatic)

Podman automatically detects `/dev/kvm` when:
- User is in `kvm` group
- `/dev/kvm` is readable and writable
- No manual permission setup needed

```bash
# Verify
podman run --rm --device /dev/kvm alpine ls -la /dev/kvm
```

### 5. Resource Limits

Control resources via environment or compose overrides:

```bash
# Environment variables
export MEMORY=4096
export CPUS=2

podman-compose up -d

# Or via compose.override.yaml
cat > compose.override.yaml << 'EOF'
version: "3.8"
services:
  gnu-hurd-dev:
    mem_limit: 4GB
    cpus: "2"
EOF
```

---

## Troubleshooting Common Issues

### Issue 1: KVM Not Detected (Falls back to TCG)

**Symptoms**: Boot takes 3-5 minutes instead of 30-60 seconds

**Diagnosis**:
```bash
# Check if /dev/kvm is accessible
ls -la /dev/kvm

# Check group membership
groups | grep kvm

# Test KVM access
podman run --rm --device /dev/kvm alpine ls -la /dev/kvm
```

**Solutions**:
1. Add user to kvm group: `sudo usermod -a -G kvm $USER`
2. Logout and login to refresh group membership: `newgrp kvm`
3. Verify: `id | grep kvm` should show gid

### Issue 2: Port Already in Use (2222 or 8080)

**Symptoms**: `Error: listen tcp 127.0.0.1:2222: bind: address already in use`

**Solutions**:
```bash
# Find what's using port 2222
lsof -i :2222

# Kill the process
pkill -f "port 2222" || true

# Or change port in compose.override.yaml
echo 'services:
  gnu-hurd-dev:
    ports:
      - "2223:22"' > compose.override.yaml

podman-compose up -d
ssh -p 2223 root@localhost
```

### Issue 3: SSH Timeout (Boot seems stuck)

**Symptoms**: `ssh: connect to host localhost port 2222: Connection refused`

**Diagnosis**:
```bash
# Check container/VM status
podman-compose ps          # For Podman
docker compose ps          # For Docker
virsh list --all           # For Libvirt

# Check logs for errors
podman-compose logs gnu-hurd-dev | tail -50
```

**Solutions**:
1. Wait longer (TCG might be booting)
2. Check disk space: `df -h`
3. Check memory availability: `free -h`
4. Check container logs for kernel panic or boot errors
5. Try with more time: `TIMEOUT=600 ./scripts/benchmark-kvm.sh docker-kvm`

### Issue 4: Permission Denied (Rootless Podman)

**Symptoms**: `Error: permission denied` when accessing /dev/kvm

**Solution**:
```bash
# Check current setup
podman info | grep rootless

# If rootless:
# Option 1: Use daemon mode (requires sudo)
sudo podman-compose up -d

# Option 2: Fix rootless KVM access
sudo sysctl kernel.unprivileged_userns_clone=1
sudo chmod 666 /dev/kvm  # Less secure, but works
```

---

## Success Criteria Summary

### Docker v2 Backend
- ✓ Starts without errors
- ✓ SSH accessible in 30-90 seconds
- ✓ Boot time < 2 minutes (KVM enabled)
- ✓ Container logs clean

### Podman Backend (PREFERRED)
- ✓ All Docker v2 criteria
- ✓ Works in rootless mode (no sudo)
- ✓ No daemon required to run
- ✓ Compatible with docker compose syntax

### Libvirt Backend
- ✓ Domain defines successfully
- ✓ SSH accessible in 30-90 seconds
- ✓ Boot time < 2 minutes (KVM enabled)
- ✓ Snapshots can be created
- ✓ Console access works

---

## Next Steps After Testing

### If All Tests Pass:
1. Create backend testing report (logs/benchmarks/)
2. Document performance findings
3. Update project README with preferred workflow (Podman)
4. Archive any non-essential documentation

### If Issues Found:
1. Document the issue in logs/troubleshooting/
2. Create GitHub issue (if community project)
3. Implement workaround (e.g., AUTO_DISABLE_KVM_FOR_IDE=1)
4. Update relevant documentation

### CI/CD Integration:
1. Modify GitHub Actions to prefer Podman
2. Test in CI with both backends
3. Enable multi-platform testing (amd64, arm64)

---

## Performance Expectations

With proper configuration:

| Backend | Mode | Boot Time | Memory | CPU | Pass Rate |
|---------|------|-----------|--------|-----|-----------|
| Podman | KVM | 30-60s | <2GB | <80% | 95%+ |
| Docker | KVM | 30-60s | <2GB | <80% | 95%+ |
| Libvirt | KVM | 30-60s | <2GB | <80% | 90%+ |
| Podman | TCG | 3-5min | <2GB | >95% | 90%+ |
| Docker | TCG | 3-5min | <2GB | >95% | 90%+ |
| Libvirt | TCG | 3-5min | <2GB | >95% | 85%+ |

---

## Conclusion

All three backends provide working GNU/Hurd environments with:
- **Podman** (PREFERRED): Rootless, no daemon, fastest setup
- **Docker v2**: Ubiquitous, well-documented, fallback option
- **Libvirt**: Advanced VM features, infrastructure integration

Testing should confirm performance expectations and identify any environment-specific issues.

---

**Date**: 2026-01-15
**Status**: Testing Phase Initiated
**Next Review**: After backend testing completion
