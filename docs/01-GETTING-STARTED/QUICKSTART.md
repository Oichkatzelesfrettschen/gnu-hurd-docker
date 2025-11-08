# GNU/Hurd Docker - Quick Start Guide

**Last Updated**: 2025-11-07
**Consolidated From**:
- QUICKSTART.md (2025-11-06)
- QUICKSTART-CI-SETUP.md (CI-focused)
- SIMPLE-START.md (Docker pull method)

**Purpose**: Get Debian GNU/Hurd x86_64 running in under 10 minutes

**Scope**: Debian GNU/Hurd x86_64 only (i386 deprecated 2025-11-07)

---

## Method 1: Docker Pull (Fastest - 3 Commands)

**Best for**: Quick testing, trying Hurd without cloning repository

```bash
# 1. Pull pre-built image
docker pull ghcr.io/oichkatzelesfrettschen/gnu-hurd-x86_64:latest

# 2. Download Hurd x86_64 image (~355 MB download, ~4 GB extracted)
wget https://cdimage.debian.org/cdimage/ports/latest/hurd-amd64/debian-hurd-amd64-20250807.img.tar.xz
tar xJf debian-hurd-amd64-20250807.img.tar.xz

# 3. Run it
docker run -d \
  --name hurd-x86_64 \
  -p 2222:2222 -p 5555:5555 -p 8080:8080 \
  -v $(pwd):/opt/hurd-image \
  --device /dev/kvm:/dev/kvm:rw \
  ghcr.io/oichkatzelesfrettschen/gnu-hurd-x86_64:latest
```

**Wait 5-10 minutes for boot**, then connect via SSH:
```bash
ssh -p 2222 root@localhost
# Default password: root (or empty - try pressing Enter)
```

---

## Method 2: Git Clone (Recommended for Development)

**Best for**: Development, customization, building from source

```bash
# 1. Clone repository
git clone https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker.git
cd gnu-hurd-docker

# 2. Download Hurd x86_64 image
./scripts/download-image.sh

# 3. Build and start
docker-compose build
docker-compose up -d

# 4. Monitor boot (optional)
docker-compose logs -f
```

**Wait 5-10 minutes for boot**, then connect via SSH:
```bash
ssh -p 2222 root@localhost
```

---

## Method 3: AUR Package (Arch Linux Only)

**Best for**: Arch Linux users, managed installation

```bash
# Using yay
yay -S gnu-hurd-docker

# Using paru
paru -S gnu-hurd-docker
```

**After installation:**
```bash
gnu-hurd-docker download  # Download Hurd x86_64 image
gnu-hurd-docker build     # Build Docker image
gnu-hurd-docker start     # Start environment
gnu-hurd-docker logs      # View logs
gnu-hurd-docker shell     # SSH into guest
```

---

## First Login and Setup

### Access the System

**Via SSH (after boot completes):**
```bash
ssh -p 2222 root@localhost
# Password: root (or empty)
```

**Via Serial Console (for boot debugging):**
```bash
telnet localhost 5555
```

**Via VNC (if ENABLE_VNC=1 in docker-compose.yml):**
```bash
# Install VNC client first
vncviewer localhost:5900
```

### Verify Architecture

```bash
# Inside guest
uname -m
# Expected: x86_64

uname -a
# Expected: GNU/Hurd ... x86_64
```

### Initial Configuration

```bash
# Set root password
passwd

# Update package lists
apt-get update

# Check available memory
free -h
# Expected: ~4 GB total

# Test network
ping -c 3 8.8.8.8
```

---

## System Credentials

```
Username: root
Password: root (or empty - varies by Debian release)

SSH Port:    localhost:2222 -> guest:22
HTTP Port:   localhost:8080 -> guest:80
Serial:      telnet localhost 5555
Monitor:     telnet localhost:9999
VNC:         localhost:5900 (if ENABLE_VNC=1)
```

---

## Current Configuration (x86_64)

```yaml
Architecture: x86_64 (pure, no i386)
System:       Debian GNU/Hurd 2025 (hurd-amd64)
CPU:          qemu64 or host (with KVM)
RAM:          4 GB (default, configurable)
SMP:          2 cores (Hurd 2025 has SMP support)
Acceleration: KVM (Linux) or TCG (macOS/Windows)
Disk:         IDE interface (Hurd-compatible)
Network:      e1000 NIC (Hurd-compatible)
Display:      nographic (default) or VNC
```

---

## Post-Installation Setup

### Mount Shared Directory

Share files between host and guest via 9p:

```bash
# Inside guest
mkdir -p /mnt/host
mount -t 9p -o trans=virtio scripts /mnt/host
ls /mnt/host
```

**On host**, place files in `./share/` to access from guest at `/mnt/host/`.

### Install Development Tools

If using the git clone method, installation scripts are available:

```bash
# Inside guest, after mounting /mnt/host
cd /mnt/host

# Option 1: Run all installations
bash run-all-installations.sh

# Option 2: Run individually
bash install-essentials-hurd.sh  # SSH, network, dev tools (required)
bash install-nodejs-hurd.sh      # Node.js (optional)
```

**What gets installed:**
- SSH server (openssh-server)
- Network tools (curl, wget, net-tools)
- Development tools (gcc, g++, make, cmake, git)
- Hurd-specific packages (gnumach-dev, hurd-dev, mig)
- Text browsers (lynx, w3m)
- Python 3, vim, emacs

---

## Quick Verification

```bash
# Check Hurd development packages
dpkg -l | grep -E "gnumach-dev|hurd-dev|mig"

# Check architecture
uname -m
# Expected: x86_64

# Check development tools
which gcc g++ make cmake git

# Check MIG (Mach Interface Generator)
which mig
# Expected: /usr/bin/mig

# Test network
ping -c 3 debian.org
```

---

## Common Tasks

### Update Packages
```bash
apt-get update
apt-get upgrade
```

### Install Additional Packages
```bash
apt-get install <package-name>

# Examples:
apt-get install vim git python3-pip
apt-get install gnumach-dev hurd-dev  # Hurd development headers
```

### Create User Account
```bash
adduser developer
usermod -aG sudo developer

# Switch to new user
su - developer
```

### Create Snapshot
```bash
# On host
./scripts/manage-snapshots.sh create initial-setup
```

---

## Port Mappings

```
Host Port -> Container -> Guest Port
--------------------------------------
2222      -> 2222      -> 22   (SSH)
8080      -> 8080      -> 80   (HTTP)
5555      -> 5555      -> N/A  (Serial console)
9999      -> 9999      -> N/A  (QEMU monitor)
5900      -> 5900      -> N/A  (VNC, if enabled)
```

---

## Performance Notes

### With KVM (Linux)

```
Boot time:     2-5 minutes
CPU:           ~80-90% of native
Responsiveness: Good
Requirements:  /dev/kvm accessible
```

### Without KVM (TCG - macOS/Windows)

```
Boot time:     5-10 minutes
CPU:           ~10-20% of native
Responsiveness: Adequate for development
Requirements:  None (works anywhere)
```

**x86_64 is slower than i386** (expected - less optimized Hurd port), but it's the future.

---

## Troubleshooting

### Container Won't Start

```bash
# Check Docker is running
docker ps

# Check logs
docker-compose logs

# Check disk space
df -h .
# Need at least 10 GB free
```

### SSH Connection Refused

```bash
# Wait longer - x86_64 boot takes 5-10 minutes
docker-compose logs -f | grep -i ssh

# Check via serial console
telnet localhost 5555

# Manually start SSH inside guest
service ssh start
```

### Slow Boot / Performance

```bash
# Enable KVM (Linux only)
# In docker-compose.yml, uncomment:
devices:
  - /dev/kvm:/dev/kvm:rw

# Increase resources
# In docker-compose.yml:
environment:
  QEMU_RAM: 8192  # More RAM
  QEMU_SMP: 4     # More CPUs
```

### Can't Access Shared Directory

```bash
# Inside guest
mount -t 9p -o trans=virtio scripts /mnt/host

# Verify on host that ./share/ exists
ls -la share/
```

---

## Next Steps

### For Development

1. **Read Architecture Docs**:
   - `docs/02-ARCHITECTURE/SYSTEM-DESIGN.md` - Understanding the system
   - `docs/03-CONFIGURATION/QEMU-CONFIGURATION.md` - Tuning QEMU

2. **Install Hurd Development Packages**:
   ```bash
   apt-get install gnumach-dev hurd-dev mig
   ```

3. **Build Something**:
   ```bash
   # Example: Build a simple Mach program
   cat > hello-mach.c << 'EOF'
   #include <mach.h>
   #include <stdio.h>

   int main() {
       printf("Hello from Mach on x86_64!\n");
       printf("Task port: %u\n", mach_task_self());
       return 0;
   }
   EOF

   gcc -o hello-mach hello-mach.c
   ./hello-mach
   ```

### For CI/CD

1. **Read CI/CD Guide**: `docs/05-CI-CD/SETUP.md`
2. **Setup GitHub Actions**: Use provided workflows
3. **Create Pre-Provisioned Image**: For faster CI runs

### For Troubleshooting

1. **Read Troubleshooting Guide**: `docs/06-TROUBLESHOOTING/COMMON-ISSUES.md`
2. **Check Specific Fixes**: `docs/06-TROUBLESHOOTING/FSCK-ERRORS.md`
3. **Report Issues**: https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker/issues

---

## Full Documentation

For detailed installation and configuration:

- **Complete Installation**: `docs/01-GETTING-STARTED/INSTALLATION.md`
- **System Requirements**: `docs/01-GETTING-STARTED/REQUIREMENTS.md`
- **Architecture Overview**: `docs/02-ARCHITECTURE/`
- **Configuration Guide**: `docs/03-CONFIGURATION/`
- **Operations Manual**: `docs/04-OPERATION/`
- **Troubleshooting**: `docs/06-TROUBLESHOOTING/`

---

## Why x86_64 Only?

As of 2025-11-07, this repository focuses exclusively on x86_64:

**Reasons:**
- Debian GNU/Hurd 2025 officially supports x86_64 (hurd-amd64)
- x86_64 is the future of Hurd development
- Cleaner architecture (no multi-arch complexity)
- Better alignment with modern hardware

**Trade-offs:**
- Slower boot/performance than i386 (less optimized)
- Higher memory usage
- Some packages may have fewer optimizations

**This is the correct direction** - Hurd's future is x86_64.

---

**Ready to go! Enjoy GNU/Hurd x86_64 development!**

---

**Status**: Production Ready (x86_64-only)
**Last Updated**: 2025-11-07
**Maintainer**: Oichkatzelesfrettschen
**Architecture**: Pure x86_64
