# GNU/Hurd x86_64 - Quick Start Guide

**Last Updated**: 2025-11-07
**Consolidated From**:
- Original: QUICKSTART.md (2025-11-06)
- Integrated: SIMPLE-START.md (historical)
- Lessons: X86_64-ONLY-SETUP.md (migration experience)

**Purpose**: Get Debian GNU/Hurd x86_64 running in under 5 minutes

**Scope**: Debian GNU/Hurd x86_64 only (i386 deprecated 2025-11-07)

---

## Prerequisites

| Requirement | Version | Purpose |
|------------|---------|---------|
| Docker | 20.10+ | Container runtime |
| Docker Compose | 2.0+ | Orchestration |
| KVM (Linux) | N/A | Hardware acceleration (optional but recommended) |
| Disk Space | 10 GB free | VM image + overhead |
| RAM | 8 GB minimum | QEMU + x86_64 Hurd needs memory |

**Check KVM availability**:
```bash
ls -l /dev/kvm
# Should show: crw-rw----+ 1 root kvm

# If missing, install and configure:
sudo apt-get install qemu-kvm  # Debian/Ubuntu
sudo pacman -S qemu-system-x86  # Arch/CachyOS
sudo usermod -aG kvm $USER      # Add yourself to kvm group
# Logout and login for group to take effect
```

---

## Method 1: Quick Start (Docker Compose - Recommended)

**Time**: 5 minutes + 5-10 minute VM boot

```bash
# 1. Clone repository
git clone https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker.git
cd gnu-hurd-docker

# 2. Verify you have the x86_64 image
ls -lh debian-hurd-amd64-80gb.qcow2
# Should show: ~2.2 GB file

# 3. Start the VM
docker-compose up -d

# 4. Monitor boot progress (optional)
docker logs -f hurd-amd64-dev

# 5. Wait for boot (x86_64 Hurd takes 5-10 minutes on first boot)
echo "Waiting 10 minutes for x86_64 Hurd boot..."
sleep 600

# 6. SSH into the running system
ssh -p 2223 root@localhost
# Password: (press Enter) or "root"
```

**Inside the VM**:
```bash
# Verify architecture
uname -m
# Should output: x86_64

# Check system
uname -a
# Should show: GNU/Hurd with x86_64
```

---

## Method 2: Docker Pull (Pre-built Image from GHCR)

**Time**: 3 minutes + image download + VM boot

```bash
# 1. Pull pre-built container image
docker pull ghcr.io/oichkatzelesfrettschen/gnu-hurd-docker:latest

# 2. Download Debian Hurd x86_64 disk image
# Option A: Use existing image
ls -lh debian-hurd-amd64-80gb.qcow2  # If you already have it

# Option B: Download fresh image (recommended if starting fresh)
# Note: Official Debian Hurd images are i386 only as of 2025-08
# This project provides pre-configured x86_64 images
# See docs/05-CI-CD/IMAGE-BUILDING.md for creating custom images

# 3. Run with Docker directly
docker run -d --privileged \
  --name hurd-amd64-dev \
  --device /dev/kvm \
  -p 2223:2222 \
  -p 8081:8080 \
  -p 5902:5901 \
  -p 5556:5555 \
  -v $(pwd)/debian-hurd-amd64-80gb.qcow2:/opt/hurd-image/debian-hurd-amd64-80gb.qcow2 \
  -v $(pwd)/share:/mnt/share:rw \
  -e QEMU_DRIVE=/opt/hurd-image/debian-hurd-amd64-80gb.qcow2 \
  -e QEMU_CPU=host \
  -e QEMU_SMP=4 \
  -e QEMU_RAM=8192 \
  -e DISPLAY_MODE=vnc \
  ghcr.io/oichkatzelesfrettschen/gnu-hurd-docker:latest

# 4. Wait and connect
sleep 600  # 10 minutes for boot
ssh -p 2223 root@localhost
```

---

## System Credentials

```
SSH:
  Host: localhost
  Port: 2223 (host) → 2222 (container) → 22 (guest)
  Username: root
  Password: (press Enter) or "root"

VNC (Graphical Console):
  Host: localhost:5902
  Display: :2

Serial Console (Text):
  telnet localhost 5556

HTTP (if web server installed in guest):
  http://localhost:8081
```

---

## Current x86_64 Configuration

```yaml
Architecture: x86_64 (amd64)
QEMU Binary: qemu-system-x86_64
Base Image: Debian GNU/Hurd 13 x86_64 (custom-built from upstream)

Hardware:
  CPU Model: host (KVM passthrough, native x86_64)
  CPU Cores: 4
  RAM: 8 GB
  Storage: SATA/AHCI (80 GB dynamic qcow2)
  Network: E1000 (proven stable with Hurd)

Acceleration:
  KVM: Enabled (if /dev/kvm available)
  TCG: Fallback (software emulation if no KVM)

Ports (host → container → guest):
  2223 → 2222 → 22   (SSH)
  8081 → 8080 → 80   (HTTP)
  5902 → 5901        (VNC, QEMU service)
  5556 → 5555        (Serial console, QEMU service)
```

---

## Boot Time Expectations

### x86_64 vs i386 (Deprecated)

| Metric | x86_64 (Current) | i386 (Deprecated) |
|--------|------------------|-------------------|
| **First Boot** | 8-12 minutes | 2-3 minutes |
| **Subsequent Boots** | 5-8 minutes | 1-2 minutes |
| **Why Slower?** | Less optimized, more RAM init, larger binaries | Mature codebase, minimal RAM |

**Why x86_64 is slower**:
1. **Newer Architecture**: Hurd x86_64 port is less mature than i386
2. **Memory Initialization**: 8 GB RAM vs 2 GB takes longer
3. **Network Detection**: E1000 enumeration slower on x86_64
4. **Binary Size**: 64-bit binaries are larger, more disk I/O

**This is normal and expected**. Be patient during first boot.

---

## Monitoring Boot Progress

### Option 1: Docker Logs
```bash
docker logs -f hurd-amd64-dev

# Look for:
# - "Booting GNU/Hurd"
# - "Starting SSH server"
# - "Network configured"
```

### Option 2: Serial Console (Real-time)
```bash
telnet localhost 5556

# You'll see:
# - GRUB boot messages
# - Kernel initialization
# - Service startup messages
#
# Press Ctrl+] then 'quit' to exit telnet
```

### Option 3: VNC (Graphical Console)
```bash
vncviewer localhost:5902

# Or use any VNC client:
# - TigerVNC: vncviewer
# - RealVNC: vnc://localhost:5902
# - Web: noVNC (if configured)
```

### Option 4: Check QEMU Process
```bash
# Verify QEMU is running
docker exec hurd-amd64-dev ps aux | grep qemu-system

# Expected output:
# qemu-system-x86_64 -m 8192 -smp 4 -cpu host -enable-kvm ...
```

---

## Verification Checklist

After SSH login:

```bash
# 1. Architecture verification
uname -m
# Expected: x86_64

# 2. System information
uname -a
# Expected: GNU mach 1.8+git... x86_64 x86_64 x86_64 GNU/Hurd

# 3. Check memory
free -h
# Expected: ~7.5 GB available (8 GB - kernel overhead)

# 4. Check CPU cores
nproc
# Expected: 4

# 5. Network connectivity
ping -c 3 google.com
# Expected: 3 packets transmitted, 3 received

# 6. Check disk space
df -h /
# Expected: ~75 GB available (80 GB - system overhead)

# 7. Package manager
apt-get update
# Expected: Package lists updated

# 8. Verify KVM in use (from host)
docker exec hurd-amd64-dev ps aux | grep qemu | grep -o '\-enable-kvm'
# Expected: -enable-kvm (if KVM available)
```

---

## Troubleshooting

### Issue: SSH Connection Refused After 10 Minutes

**Symptom**: `ssh: connect to host localhost port 2223: Connection refused`

**Diagnosis**:
```bash
# 1. Check if VM is still booting
docker logs hurd-amd64-dev | tail -20

# 2. Check QEMU process
docker exec hurd-amd64-dev ps aux | grep qemu-system-x86_64
# If no output, QEMU crashed

# 3. Check serial console
telnet localhost 5556
# See actual boot messages
```

**Solutions**:
```bash
# If QEMU crashed:
docker-compose down
docker-compose up -d
# Wait another 10 minutes

# If still booting (x86_64 can take 12+ minutes on first boot):
sleep 300  # Wait 5 more minutes
ssh -p 2223 root@localhost

# If VNC shows kernel panic:
# See docs/06-TROUBLESHOOTING/KERNEL-FIXES.md
```

### Issue: KVM Not Available

**Symptom**: `KVM acceleration: DISABLED` in logs

**Check**:
```bash
ls -l /dev/kvm
# If permission denied:
sudo usermod -aG kvm $USER
# Logout and login
```

**Impact**: VM will use TCG (software emulation), expect 2-3x slower boot

**Workaround**: This is fine for development, just slower

### Issue: Out of Disk Space

**Symptom**: QCOW2 image won't start, `No space left on device`

**Check**:
```bash
df -h .
# Need at least 10 GB free
```

**Solution**:
```bash
# Free up space, or move repository to larger partition
mv gnu-hurd-docker /path/to/larger/partition/
cd /path/to/larger/partition/gnu-hurd-docker
docker-compose up -d
```

### Issue: Port Already in Use

**Symptom**: `Error starting userland proxy: listen tcp4 0.0.0.0:2223: bind: address already in use`

**Solution**:
```bash
# Find what's using the port
sudo lsof -i :2223

# Kill it or change docker-compose.yml port mapping:
# ports:
#   - "2224:2222"  # Use 2224 instead of 2223
```

---

## Next Steps

Once SSH works:

1. **Explore the system**: See [docs/04-OPERATION/SSH-ACCESS.md](../04-OPERATION/SSH-ACCESS.md)
2. **Install packages**: See [docs/04-OPERATION/PACKAGE-MANAGEMENT.md](../04-OPERATION/PACKAGE-MANAGEMENT.md)
3. **Configure networking**: See [docs/03-CONFIGURATION/NETWORK-PORTS.md](../03-CONFIGURATION/NETWORK-PORTS.md)
4. **Development setup**: See [docs/04-OPERATION/DEVELOPMENT-ENVIRONMENT.md](../04-OPERATION/DEVELOPMENT-ENVIRONMENT.md)

---

## Quick Reference Commands

```bash
# Start VM
docker-compose up -d

# Stop VM
docker-compose down

# Restart VM
docker-compose restart

# View logs (real-time)
docker logs -f hurd-amd64-dev

# SSH into VM
ssh -p 2223 root@localhost

# Serial console
telnet localhost 5556

# VNC viewer
vncviewer localhost:5902

# Check VM status
docker ps | grep hurd-amd64-dev

# Rebuild container (after Dockerfile changes)
docker-compose build
docker-compose up -d
```

---

## Lessons Learned (Migration from i386)

### What Changed
- **Architecture**: i386 → x86_64 (complete migration Nov 2025)
- **Boot Time**: 2-3 min → 8-12 min (expected, x86_64 less mature)
- **Memory**: 2 GB → 8 GB (x86_64 needs more for optimal performance)
- **CPU**: Pentium 3 → host (KVM passthrough, native performance)
- **Storage**: IDE → SATA/AHCI (better x86_64 compatibility)

### Why This Matters
1. **Future-Proof**: x86_64 is the path forward for Hurd
2. **More Memory**: Modern applications need > 2 GB
3. **Better Testing**: Test on target architecture (x86_64)
4. **Community**: Contributing to x86_64 Hurd maturity

### What to Expect
- Longer boot times (be patient)
- Occasional quirks (x86_64 port still maturing)
- Better long-term stability (64-bit address space, more RAM)

---

## Document History

### Original Authors/Sessions
- 2025-11-06: Initial QUICKSTART.md (i386 focus)
- 2025-11-06: SIMPLE-START.md (Docker pull workflow)
- 2025-11-07: X86_64-ONLY-SETUP.md (migration experience)

### Major Revisions
- 2025-11-07: Consolidated from 3 source documents + x86_64 migration

---

END OF QUICK START GUIDE

**Next**: [Installation Guide (Manual Setup)](INSTALLATION.md) | [Return to Index](../INDEX.md)
