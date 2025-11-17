# Building a "Riced" GNU/Hurd Image

**Document Version:** 1.0
**Last Updated:** 2025-11-05
**Scope:** Complete guide to building a pre-configured Hurd development image

---

## Overview

This guide explains how to create a "riced" (fully-configured) GNU/Hurd QCOW2 image with all development tools pre-installed and user accounts configured. This image can then be distributed via Docker for instant deployment.

**"Riced"** means:
- All development tools pre-installed (~1.5 GB packages)
- root and agents accounts configured
- Shell environment customized
- Ready for immediate development work

---

## Prerequisites

### Required

- Docker and Docker Compose installed
- 10 GB free disk space (8 GB for images, 2 GB for building)
- Network connectivity (for apt-get package downloads)
- 4 GB RAM minimum (for QEMU allocation)

### Recommended

- 16 GB RAM (allows comfortable build process)
- SSD storage (faster I/O during package installation)
- Fast network (20-30 minute download vs 1+ hour on slow connections)

---

## Method 1: Automated Build (Recommended)

### Overview

This method boots a vanilla Debian Hurd image, runs all setup scripts automatically, and creates a snapshot.

### Steps

#### 1. Prepare Environment

```bash
cd /path/to/gnu-hurd-docker

# Ensure you have the vanilla Debian Hurd image
ls -lh debian-hurd-i386-20251105.qcow2

# If not present, download it:
./scripts/download-image.sh
```

#### 2. Start Docker Container

```bash
# Build Docker image
docker-compose build

# Start container
docker-compose up -d

# Wait for boot (2-3 minutes)
sleep 180

# Check logs
docker-compose logs -f
```

#### 3. Connect and Run Setup Scripts

```bash
# Connect to Hurd via SSH
ssh root@localhost -p 2222
# Password: (default from Debian image, usually no password or "root")

# Inside Hurd, copy scripts
# (They should be visible at /opt/hurd-image/scripts if volume is mounted)

# Run setup scripts in order
cd /opt/hurd-image/scripts

# 1. Install development tools (~20-30 minutes)
./setup-hurd-dev.sh

# 2. Configure users (2 minutes)
./configure-users.sh

# 3. Configure shell for root
./configure-shell.sh

# 4. Configure shell for agents
su - agents
cd /opt/hurd-image/scripts
./configure-shell.sh
exit

# 5. Test configuration
mach-sysinfo
mig-version
```

#### 4. Clean Up and Shutdown

```bash
# Clean package cache to save space
apt-get clean

# Remove temporary files
rm -rf /tmp/* /var/tmp/*

# Graceful shutdown
shutdown -h now
```

#### 5. Commit Changes to Image

```bash
# Wait for shutdown to complete
docker-compose logs | tail -20

# Stop container
docker-compose down

# Optional: Create snapshot before committing
./scripts/manage-snapshots.sh create pre-rice

# The QCOW2 now contains all changes (copy-on-write)
ls -lh debian-hurd-i386-20251105.qcow2

# Optional: Compress image (reduces size by ~30%)
qemu-img convert -O qcow2 -c \
  debian-hurd-i386-20251105.qcow2 \
  debian-hurd-riced-$(date +%Y%m%d).qcow2
```

#### 6. Update Docker Configuration

```bash
# Update entrypoint.sh to use new image name (if renamed)
sed -i 's/debian-hurd-i386-20251105.qcow2/debian-hurd-riced-20251105.qcow2/' entrypoint.sh

# Update docker-compose.yml (no changes needed if using same filename)

# Rebuild Docker image with new QCOW2
docker-compose build --no-cache
```

---

## Method 2: Manual Build (Alternative)

### Overview

Run QEMU directly without Docker, configure manually, then import into Docker.

### Steps

#### 1. Boot QEMU Directly

```bash
qemu-system-i386 \
  -m 2048 \
  -cpu pentium3 \
  -drive file=debian-hurd-i386-20251105.qcow2,format=qcow2 \
  -net user,hostfwd=tcp::2222-:22 \
  -net nic,model=e1000 \
  -nographic \
  -serial pty
```

#### 2. Follow Same Configuration Steps

(Same as Method 1, steps 3-4)

#### 3. Commit and Move to Docker

```bash
# Shutdown QEMU
# (From inside Hurd: shutdown -h now)

# Move riced image to Docker directory
mv debian-hurd-i386-20251105.qcow2 /path/to/gnu-hurd-docker/

# Build Docker image
cd /path/to/gnu-hurd-docker
docker-compose build
```

---

## Method 3: Scripted Automation (Advanced)

### Overview

Fully automated build using expect scripts or similar automation.

### Tools Required

- `expect` (for automating SSH interaction)
- `sshpass` (for password automation)
- `pexpect` (Python library, alternative)

### Example Automation Script

```bash
#!/bin/bash
# Automated Hurd image builder
set -e

echo "Starting automated Hurd image build..."

# Start Docker
docker-compose up -d

# Wait for SSH
echo "Waiting for SSH..."
for i in {1..60}; do
  if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=2 \
     root@localhost -p 2222 "echo OK" 2>/dev/null; then
    echo "SSH ready"
    break
  fi
  sleep 5
done

# Run setup scripts via SSH
ssh -o StrictHostKeyChecking=no root@localhost -p 2222 << 'REMOTE_SCRIPT'
set -e
cd /opt/hurd-image/scripts

# Setup development tools
./setup-hurd-dev.sh <<< 'y'

# Configure users
./configure-users.sh

# Configure shells
./configure-shell.sh
su - agents -c './configure-shell.sh'

# Clean up
apt-get clean
rm -rf /tmp/* /var/tmp/*

# Shutdown
shutdown -h now
REMOTE_SCRIPT

echo "Waiting for shutdown..."
sleep 30

# Stop container
docker-compose down

echo "Build complete!"
```

---

## Verification Checklist

After building, verify the riced image:

### Boot Test

```bash
docker-compose up -d
docker-compose logs -f
# Look for: "Starting QEMU GNU/Hurd..."
```

### Login Test

```bash
# Test root login
ssh root@localhost -p 2222
# Password: root

# Test agents login
ssh agents@localhost -p 2222
# Password: agents
```

### Development Tools Test

```bash
# Inside Hurd as agents
gcc --version        # Should show GCC
mig --version        # Should show MIG
cmake --version      # Should show CMake
git --version        # Should show Git
```

### Sudo Test

```bash
# As agents user
sudo whoami          # Should output: root (NOPASSWD)
```

### Shell Configuration Test

```bash
# As agents user
mach-sysinfo         # Should display system info
mach-rebuild         # Should exist as function
ll                   # Should be aliased (colorized ls)
```

---

## Distribution

### Package as Docker Image

```bash
# Build final Docker image
docker-compose build

# Tag with version
docker tag gnu-hurd-dev:latest gnu-hurd-dev:riced-v1.0

# Push to GHCR (if configured)
docker push ghcr.io/oichkatzelesfrettschen/gnu-hurd-docker:latest
```

### Share QCOW2 Image

```bash
# Compress QCOW2 for distribution
xz -9 -k debian-hurd-riced-20251105.qcow2
# Creates: debian-hurd-riced-20251105.qcow2.xz (~400 MB)

# Upload to release
gh release create v1.0 \
  --title "GNU/Hurd Docker v1.0 - Riced Development Image" \
  --notes "Fully-configured Hurd development environment" \
  debian-hurd-riced-20251105.qcow2.xz
```

### Include in Repository (Alternative)

**Note:** QCOW2 images are large (2-4 GB) and generally **not recommended** for Git repos.

Alternatives:
- Host on releases (GitHub Releases, S3)
- Provide download script
- Use Git LFS (if repository supports it)

---

## Troubleshooting

### Issue: Setup scripts fail during package installation

**Cause:** Network connectivity or mirror issues

**Solution:**
```bash
# Update package lists
apt-get update

# Try different mirror
sed -i 's/deb.debian.org/ftp.us.debian.org/' /etc/apt/sources.list
apt-get update
```

### Issue: Disk full during installation

**Cause:** QCOW2 virtual size too small

**Solution:**
```bash
# Resize QCOW2 (on host, while VM is shut down)
qemu-img resize debian-hurd-i386-20251105.qcow2 +5G

# Boot Hurd and resize filesystem
# (Inside Hurd)
resize2fs /dev/hd0s1   # Adjust device as needed
```

### Issue: Shutdown hangs

**Cause:** Services not stopping cleanly

**Solution:**
```bash
# Force shutdown (from host)
docker-compose down --timeout 60

# Or kill QEMU process
pkill -9 qemu-system-i386
```

### Issue: Changes lost after reboot

**Cause:** QCOW2 mounted read-only

**Solution:**
```bash
# Check docker-compose.yml volume mount
# Should be:
volumes:
  - .:/opt/hurd-image:rw   # NOT :ro
```

---

## Performance Optimization

### Faster Package Installation

```bash
# Use parallel downloads (inside Hurd)
echo 'Acquire::Queue-Mode "access";' > /etc/apt/apt.conf.d/99parallel
echo 'Acquire::http::Pipeline-Depth "5";' >> /etc/apt/apt.conf.d/99parallel
```

### Reduce Image Size

```bash
# Remove unnecessary packages
apt-get autoremove --purge

# Clean all caches
apt-get clean
rm -rf /var/cache/apt/archives/*
rm -rf /tmp/* /var/tmp/*
rm -rf /var/log/*.log

# Zero free space (improves compression)
dd if=/dev/zero of=/zero bs=1M || true
rm /zero
sync
```

### Compress for Distribution

```bash
# Best compression (slow)
qemu-img convert -O qcow2 -c -o compression_type=zstd \
  source.qcow2 output.qcow2

# Faster compression
xz -9 -T4 output.qcow2
```

---

## Automation Recommendations

### CI/CD Integration

```yaml
# .github/workflows/build-image.yml (example)
name: Build Riced Hurd Image

on:
  workflow_dispatch:
  schedule:
    - cron: '0 0 1 * *'  # Monthly

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Download base image
        run: ./scripts/download-image.sh

      - name: Build riced image
        run: ./scripts/automated-build.sh

      - name: Upload artifact
        uses: actions/upload-artifact@v3
        with:
          name: hurd-riced-image
          path: debian-hurd-riced-*.qcow2.xz
```

---

## References

- GNU Hurd Installation Guide: https://www.gnu.org/software/hurd/hurd/running.html
- QEMU Image Management: https://www.qemu.org/docs/master/system/images.html
- Debian Hurd Packages: https://www.debian.org/ports/hurd/

---

**Status:** Documentation complete - ready for image building
**Next:** Build your riced image and test!

