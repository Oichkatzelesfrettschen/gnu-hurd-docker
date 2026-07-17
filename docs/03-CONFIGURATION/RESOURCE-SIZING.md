# Resource Sizing Guide

## Overview

This document provides guidance on allocating resources (CPU, RAM, disk) to your GNU/Hurd Docker container for optimal performance and stability.

The Debian GNU/Hurd x86_64 environment in QEMU is highly configurable, and the right resource allocation depends on your use case, host capabilities, and desired performance.

## Three Configuration Profiles

### Profile 1: Minimal (Testing/Learning)

**Ideal for:** Basic CLI testing, learning, CI/CD validation

| Resource | Value | Notes |
|----------|-------|-------|
| RAM | 2 GB | Minimum for stable operation |
| CPU Cores | 1-2 | Single core acceptable for testing |
| Acceleration | TCG acceptable | KVM recommended if available |
| Disk Space | 10-15 GB | Base + working space |
| Boot Time | 5-10 min (TCG) / 2-3 min (KVM) | Varies significantly |

**Host Requirements:**
- 2+ CPU cores
- 4 GB total RAM
- 10 GB free disk space

**Configuration:**
```bash
QEMU_RAM=2048 QEMU_SMP=1 make up
# or with KVM
QEMU_RAM=2048 QEMU_SMP=1 make up-kvm
```

---

### Profile 2: Recommended (Development)

**Ideal for:** Active development, moderate builds, GUI applications

| Resource | Value | Notes |
|----------|-------|-------|
| RAM | 4 GB | Default in compose.yaml |
| CPU Cores | 2-4 | 2 stable, 4 experimental |
| Acceleration | KVM strongly recommended | ~60x faster than TCG |
| Disk Space | 20-30 GB | Includes build artifacts |
| Boot Time | 30-60 sec (KVM) / 3-5 min (TCG) | Typical deployment |

**Host Requirements:**
- 4+ CPU cores with VT-x/AMD-V
- 8 GB RAM
- 20 GB SSD storage

**Configuration:**
```bash
# Default (recommended)
make up

# Explicit
QEMU_RAM=4096 QEMU_SMP=2 make up-kvm

# With 4 cores (experimental)
QEMU_RAM=4096 QEMU_SMP=4 make up-kvm
```

---

### Profile 3: Optimal (Performance)

**Ideal for:** Large builds, desktop environment, performance testing

| Resource | Value | Notes |
|----------|-------|-------|
| RAM | 8 GB | Best performance for complex tasks |
| CPU Cores | 4-6 | Diminishing returns beyond 6 |
| Acceleration | KVM required | Only viable option for this profile |
| Disk Space | 40-60 GB | Multiple snapshots + large projects |
| Boot Time | 20-40 sec (KVM) | Fastest startup |

**Host Requirements:**
- 8+ CPU cores
- 16+ GB RAM
- 40 GB NVMe or fast SSD storage

**Configuration:**
```bash
QEMU_RAM=8192 QEMU_SMP=6 make up-kvm
```

---

## Disk Space Requirements

Complete breakdown for different usage patterns:

| Component | Size | Notes |
|-----------|------|-------|
| Debian Hurd base image | 2-4 GB | QCOW2 format (sparse) |
| Docker image layer | 1-2 GB | Ubuntu 24.04 with QEMU |
| Working space (guest) | 3-10 GB | /home, build artifacts |
| QEMU snapshots | 1-5 GB | Per snapshot |
| Logs/temporary | 0.5-1 GB | Container logs, cache |
| **Total minimum** | **10-15 GB** | Minimal profile |
| **Total recommended** | **20-30 GB** | Development profile |
| **Total optimal** | **40-60 GB** | Performance profile |

### Storage Type Impact

| Storage Type | Boot Time | Build Speed | Reliability |
|--------------|-----------|-------------|-------------|
| HDD (5400 RPM) | 8-15 min | Slow (5-10x) | Good |
| SSD (SATA) | 2-5 min | Good (2-3x faster) | Good |
| NVMe | 1-2 min | Excellent (5-10x faster) | Excellent |

**Recommendation:** Use SSD or NVMe for Profile 2+; HDD acceptable for Profile 1.

---

## Configuration Methods

### Method 1: Environment Variables (Recommended for Testing)

```bash
# Override at runtime
QEMU_RAM=4096 QEMU_SMP=2 make up-kvm

# Multiple variables
QEMU_RAM=8192 QEMU_SMP=4 QEMU_DISK_BUS=ahci make up-kvm
```

### Method 2: Docker Compose Override (Recommended for Development)

Create `compose.override.yaml`:

```yaml
services:
  gnu-hurd-dev:
    environment:
      QEMU_RAM: "4096"
      QEMU_SMP: "2"
      QEMU_DISK_BUS: "ahci"
```

Then run normally:
```bash
make up
```

### Method 3: Environment File (.env)

Create `.env` in repository root:

```bash
QEMU_RAM=4096
QEMU_SMP=2
QEMU_DISK_BUS=ahci
ENABLE_VNC=1
```

Docker Compose will automatically load this file.

### Method 4: Direct Modification (Not Recommended)

Edit `compose.yaml` directly. **Note:** This approach complicates version control.

---

## Auto-Sizing Script

The container provides intelligent auto-sizing based on host resources. To use it:

```bash
# View current configuration
docker exec gnu-hurd-dev env | grep QEMU

# Detect host resources and recommend configuration
HOST_CORES=$(nproc)
HOST_RAM_MB=$(($(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024))

# Calculate recommendations
RECOMMENDED_CORES=$((HOST_CORES / 2))
[ $RECOMMENDED_CORES -lt 2 ] && RECOMMENDED_CORES=2
[ $RECOMMENDED_CORES -gt 8 ] && RECOMMENDED_CORES=8

RECOMMENDED_RAM=$((HOST_RAM_MB / 4))
[ $RECOMMENDED_RAM -lt 2048 ] && RECOMMENDED_RAM=2048
[ $RECOMMENDED_RAM -gt 8192 ] && RECOMMENDED_RAM=8192

echo "Host: $HOST_CORES cores, ${HOST_RAM_MB}MB RAM"
echo "Recommended: QEMU_SMP=$RECOMMENDED_CORES, QEMU_RAM=$RECOMMENDED_RAM"
```

---

## Performance Characteristics

### Boot Time Comparison

| Profile | TCG | KVM | Notes |
|---------|-----|-----|-------|
| Minimal (2GB/1 core) | 5-10 min | 2-3 min | First boot slower |
| Recommended (4GB/2 cores) | 3-5 min | 30-60 sec | Typical deployment |
| Optimal (8GB/4 cores) | 2-3 min | 20-40 sec | Fastest startup |

**Factors Affecting Boot Time:**
- GitHub runner load (if in CI/CD)
- Disk I/O performance (HDD >> SSD >> NVMe)
- QEMU version and optimization
- Guest image state (clean vs. modified)

### Build Performance (GNU Hello Example)

| Profile | Configure | Compile | Total |
|---------|-----------|---------|-------|
| Minimal (1 core, TCG) | 8s | 45s | 53s |
| Minimal (2 cores, TCG) | 8s | 32s | 40s |
| Recommended (2 cores, KVM) | 2s | 8s | 10s |
| Optimal (4 cores, KVM) | 2s | 5s | 7s |

**Memory Pressure Impact:**

| RAM | Configure | Compile | Notes |
|-----|-----------|---------|-------|
| 1 GB | Timeout | OOM | Not viable |
| 2 GB | 8s | 45s | Minimal swapping |
| 4 GB | 2s | 8s | No swap |
| 8 GB | 2s | 5s | Optimal |

---

## Inside Guest: Verifying Configuration

Once the container is running, verify resource allocation:

```bash
# Check CPU cores
nproc
# Expected: matches QEMU_SMP (default 2)

# Check RAM
free -h
# Expected: matches QEMU_RAM (default 4GB)

# Check available memory for builds
available_mb=$(grep MemAvailable /proc/meminfo | awk '{print $2/1024}')
echo "Available RAM: ${available_mb} MB"

# Check storage
df -h /
# Expected: matches QEMU_DISK_SIZE (default 20GB)
```

---

## Configuration Verification Commands

### Host-Side Checks

```bash
# Verify container resource limits
docker inspect gnu-hurd-dev | jq '.HostConfig | {Memory, CpuPeriod, CpuQuota}'

# Check actual resource usage
docker stats gnu-hurd-dev --no-stream

# Verify QEMU process
ps aux | grep qemu-system
```

### Guest-Side Checks (Inside Container)

```bash
# Via SSH
ssh -p 2222 root@localhost "nproc; free -h; df -h /"

# Via serial console
docker exec gnu-hurd-dev /opt/scripts/qemu-shell-run.sh "nproc; free -h"
```

---

## Troubleshooting Resource Issues

### Slow Boot Time

**Symptoms:** Container takes 5-10+ minutes to boot

**Diagnosis:**
```bash
# Check if KVM is available
docker exec gnu-hurd-dev grep "KVM\|TCG" /tmp/qemu-startup.log

# Check QEMU_SMP (high values slow boot)
docker exec gnu-hurd-dev env | grep QEMU

# Monitor boot progress
docker logs -f gnu-hurd-dev
```

**Solutions:**
1. Enable KVM if available: `make up-kvm`
2. Reduce CPU cores: `QEMU_SMP=2 make up-kvm`
3. Check disk I/O: Use NVMe/SSD if possible
4. Try TCG-optimized profile: `QEMU_RAM=2048 QEMU_SMP=1 make up`

---

### Out of Memory Errors

**Symptoms:** Container shows "Cannot allocate memory" or "OOM killer" in logs

**Diagnosis:**
```bash
# Check guest memory usage
docker exec gnu-hurd-dev free -h

# Check for memory pressure
docker exec gnu-hurd-dev grep -E "SwapFree|MemAvailable" /proc/meminfo

# Check docker limits
docker inspect gnu-hurd-dev | jq '.HostConfig.Memory'
```

**Solutions:**
1. Increase QEMU_RAM: `QEMU_RAM=8192 make up`
2. Reduce CPU cores (less parallelism): `QEMU_SMP=2 make up`
3. Limit build parallelism: `make -j2` inside guest
4. Monitor and optimize: Use `free`, `ps aux` to identify memory hogs

---

### High Host CPU Usage

**Symptoms:** Host CPU at 100% even with idle guest

**Diagnosis:**
```bash
# Check guest CPU load
docker exec gnu-hurd-dev uptime

# Monitor QEMU process CPU usage
top -p $(pgrep -f qemu-system)
```

**Solutions:**
1. Reduce QEMU_SMP: `QEMU_SMP=2 make up`
2. Enable CPU limits: Modify `compose.yaml` CPU settings
3. Check for busy processes: `docker exec gnu-hurd-dev ps aux | sort -k3 -r | head`
4. Adjust guest scheduler: `QEMU_CPU=host-phys-bits=keep`

---

### Disk I/O Bottleneck

**Symptoms:** Compilation slow despite adequate CPU/RAM

**Diagnosis:**
```bash
# Check QEMU disk cache setting
docker inspect gnu-hurd-dev | grep -i cache

# Monitor disk I/O
docker exec gnu-hurd-dev iostat -x 1

# Check image format
file /opt/hurd-image/debian-hurd-amd64.qcow2
```

**Solutions:**
1. Optimize cache mode: Add to docker compose override:
   ```yaml
   environment:
     QEMU_DISK_CACHE: "writeback"
   ```
2. Use faster storage: Migrate to NVMe/SSD
3. Enable virtio: `QEMU_DISK_BUS=ahci make up`
4. Increase QEMU thread pool: `QEMU_AIO=threads`

---

## Best Practices

1. **Match Profile to Use Case**
   - Minimal: CI/CD, testing, learning
   - Recommended: Active development (default)
   - Optimal: Performance testing, production builds

2. **Enable KVM When Available**
   - 30-60x faster than TCG
   - Stable on Linux x86_64
   - Gracefully falls back if unavailable

3. **Use Override Files**
   - `compose.override.yaml` for persistent changes
   - Keeps main config clean
   - Easy to commit/share

4. **Monitor Resource Usage**
   - Check guest: `free -h`, `nproc`, `df -h`
   - Check host: `docker stats`, `ps aux`
   - Adjust based on workload

5. **Test Configuration Changes**
   - Start with minimal profile
   - Increase resources as needed
   - Verify improvement with benchmarks

6. **Snapshot Before Major Changes**
   - Create snapshot before `make up`
   - Easy rollback if configuration breaks
   - Useful for testing different profiles

---

## Related Documentation

- [REQUIREMENTS.md](../01-GETTING-STARTED/REQUIREMENTS.md) - System requirements
- [environment-variables.md](environment-variables.md) - Complete environment variable reference
- [QEMU-CONFIGURATION.md](../02-ARCHITECTURE/QEMU-CONFIGURATION.md) - QEMU-specific tuning
- [OPTIMIZATION-2025.md](../02-ARCHITECTURE/qemu/OPTIMIZATION-2025.md) - Advanced QEMU optimization
- [COMMON-ISSUES.md](../06-TROUBLESHOOTING/COMMON-ISSUES.md) - Issue resolution
- [PLAYBOOK.md](../06-TROUBLESHOOTING/PLAYBOOK.md) - Systematic troubleshooting guide

---

## Summary

- **2 GB RAM / 1 core** → Minimal (testing only)
- **4 GB RAM / 2 cores** → Recommended (development, default)
- **8 GB RAM / 4-6 cores** → Optimal (performance)
- **Always use KVM when available** (Linux x86_64)
- **Use SSD/NVMe for Profile 2+**
- **Override via environment variables or `compose.override.yaml`**
- **Monitor with `free`, `nproc`, `df`, `docker stats`**

Example configuration:
```bash
# Recommended development setup
QEMU_RAM=4096 QEMU_SMP=2 make up-kvm
```
