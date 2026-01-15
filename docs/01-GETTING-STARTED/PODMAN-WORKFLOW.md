# Podman Workflow Guide (Preferred)

## Overview

This guide covers using **Podman** as the preferred container runtime for GNU/Hurd development. Podman offers:

- **Rootless execution** (no daemon, better security)
- **Daemonless operation** (simpler than Docker daemon)
- **Docker-compatible syntax** (use existing docker-compose files)
- **Direct KVM access** (no special permission setup)
- **No installation hassle** (on Linux systems)

**Status**: Recommended as primary workflow

---

## Quick Start (5 minutes)

### 1. Install Podman

**Arch/CachyOS** (Recommended):
```bash
sudo pacman -S podman podman-compose qemu qemu-system-x86
```

**Ubuntu/Debian**:
```bash
sudo apt install podman podman-compose qemu qemu-system-x86
```

**Fedora/RHEL**:
```bash
sudo dnf install podman podman-compose qemu
```

### 2. Verify Installation

```bash
podman --version          # Should be 3.0+
podman-compose --version  # Should be 1.0+
```

### 3. Download Disk Image

```bash
./scripts/download-image.sh
# Creates: /var/lib/libvirt/images/debian-hurd-amd64.qcow2 (~500MB)
```

### 4. Start GNU/Hurd (Podman with KVM)

```bash
# Bring down any existing containers
podman-compose down 2>/dev/null || true

# Start with KVM acceleration
podman-compose -f docker-compose.yml -f docker-compose.kvm.yml up -d

# Wait for boot (~30-60 seconds with KVM)
sleep 30

# SSH into the system
ssh -p 2222 root@localhost
# (May take 30-90 seconds on first boot)
```

**That's it!** You have GNU/Hurd running under Podman.

---

## Why Podman Over Docker?

| Feature | Podman | Docker |
|---------|--------|--------|
| **Rootless** | ✓ Native | ⚠ Complex setup |
| **Daemonless** | ✓ Yes | ✗ Daemon required |
| **Setup Complexity** | Low | Medium |
| **Resource Overhead** | Lower | Higher |
| **Security Model** | Better | Standard |
| **Docker Compatibility** | 95%+ | 100% |
| **KVM Access** | Auto-detected | Requires setup |

**Recommendation**: Use Podman unless you specifically need Docker features.

---

## Rootless Mode (Default)

Podman runs in **rootless mode** by default on Linux:

```bash
# Verify rootless
podman info | grep rootless
# Output: rootless: true

# No sudo needed
podman-compose up -d          # Works
podman ps                     # Works
podman exec gnu-hurd-dev ls   # Works
```

### Benefits:
- No daemon running in background
- No root privilege escalation
- Better security isolation
- Direct user resource control

### KVM in Rootless Mode

KVM is automatically available in rootless mode if:
1. User is in `kvm` group: `groups | grep kvm`
2. `/dev/kvm` is readable/writable: `ls -la /dev/kvm`

To fix KVM access if needed:

```bash
# Add user to kvm group (one-time)
sudo usermod -a -G kvm $USER

# Logout and login to apply group membership
exit  # logout
# Then login again

# Verify
groups | grep kvm
```

---

## Common Workflow Commands

### Start GNU/Hurd (with KVM)

```bash
podman-compose -f docker-compose.yml -f docker-compose.kvm.yml up -d
# Or shorter:
podman-compose up -d  # Uses default compose file
```

### Stop GNU/Hurd

```bash
podman-compose down
# Data is preserved; next 'up' will reuse the same container
```

### Access Console/SSH

```bash
# SSH (recommended)
ssh -p 2222 root@localhost

# Check container logs
podman-compose logs gnu-hurd-dev

# Get container status
podman-compose ps
```

### Resource Monitoring

```bash
# Real-time stats
podman stats gnu-hurd-dev

# Memory/CPU usage
podman-compose top gnu-hurd-dev

# Environment variables
podman exec gnu-hurd-dev env | grep -E "(KVM|QEMU|MEM|CPU)"
```

### Remove Everything and Start Fresh

```bash
# Stop container
podman-compose down

# Remove container volume
podman volume rm $(podman volume ls -q) 2>/dev/null

# Start fresh
podman-compose -f docker-compose.yml -f docker-compose.kvm.yml up -d
```

---

## Customization

### Adjust Memory/CPU

Create `docker-compose.override.yml`:

```yaml
version: "3.8"
services:
  gnu-hurd-dev:
    mem_limit: "2GB"    # Minimum for boot
    cpus: "1"           # At least 1 core
```

Or via environment:

```bash
MEMORY=2048 CPUS=1 podman-compose up -d
```

### Change SSH Port

```yaml
# docker-compose.override.yml
services:
  gnu-hurd-dev:
    ports:
      - "2223:22"       # SSH on 2223 instead of 2222
```

Then: `ssh -p 2223 root@localhost`

### Disable KVM (if issues)

```bash
# Method 1: Unset overlay
podman-compose -f docker-compose.yml up -d
# (Uses default, no KVM)

# Method 2: Environment variable
AUTO_DISABLE_KVM_FOR_IDE=1 podman-compose up -d

# Method 3: Modify compose file
# Remove "-f docker-compose.kvm.yml" from command
```

### Use TCG Emulation (Slower)

For testing without KVM:

```bash
# Start without KVM overlay
podman-compose up -d
# Boot will take 3-5 minutes instead of 30-60 seconds
```

---

## Troubleshooting

### Port 2222 Already in Use

```bash
# Find what's using it
lsof -i :2222

# Kill it (or just use a different port)
# Option 1: Kill the process
pkill -f something

# Option 2: Use different port in docker-compose.override.yml
echo 'services:
  gnu-hurd-dev:
    ports:
      - "2223:22"' > docker-compose.override.yml
```

### SSH Timeout (Can't connect)

```bash
# Wait longer (TCG boot is slow)
sleep 120 && ssh -p 2222 root@localhost

# Check if container is running
podman ps | grep gnu-hurd

# Check logs for errors
podman-compose logs | tail -50

# If container exited, check why
podman-compose up -d  # Try again
```

### Out of Memory

```bash
# Check available memory
free -h

# Reduce container memory limit
echo 'services:
  gnu-hurd-dev:
    mem_limit: "2GB"' > docker-compose.override.yml

podman-compose down
podman-compose up -d
```

### Permission Denied

```bash
# If you get "permission denied" errors:

# Option 1: Add to kvm group (recommended)
sudo usermod -a -G kvm $USER
newgrp kvm
podman-compose up -d

# Option 2: Use daemon mode (less secure)
sudo podman-compose up -d
```

---

## Performance Tips

### 1. Use KVM (30-60s boot time)

Always include the KVM overlay:

```bash
podman-compose -f docker-compose.yml -f docker-compose.kvm.yml up -d
```

Verify KVM is used:

```bash
ssh -p 2222 root@localhost "grep -i kvm /proc/cpuinfo" && echo "KVM enabled" || echo "TCG fallback"
```

### 2. Monitor Performance

```bash
# While booting, watch CPU/memory
watch -n 1 'podman stats gnu-hurd-dev --no-stream'

# In another terminal, monitor disk I/O
iostat 1
```

### 3. Ensure Sufficient Resources

```bash
# Check available resources
free -h   # RAM
df -h     # Disk space
nproc     # CPU cores
```

Minimum recommended:
- RAM: 2GB (VM) + 2GB (host) = 4GB total
- Disk: 20GB free (VM image + working space)
- CPUs: 2 cores

### 4. Close Unnecessary Applications

Large applications competing for resources slow boot:

```bash
# Stop heavy services temporarily
sudo systemctl stop heavy-service  # e.g., Virtualbox, docker daemon

# Boot Hurd
podman-compose up -d
```

---

## Integration with Development Workflow

### Build Inside GNU/Hurd

```bash
ssh -p 2222 root@localhost

# Inside the VM:
cd /root
apt install build-essential
gcc --version

# Your development here
```

### Share Files with Host

Use bind mount:

```yaml
# docker-compose.override.yml
services:
  gnu-hurd-dev:
    volumes:
      - /home/user/projects:/root/projects:rw
```

Then:

```bash
podman-compose down && podman-compose up -d
ssh -p 2222 root@localhost "ls /root/projects"
```

### Port Forwarding for Services

Map additional ports:

```yaml
# docker-compose.override.yml
services:
  gnu-hurd-dev:
    ports:
      - "2222:22"     # SSH
      - "8080:80"     # HTTP
      - "3000:3000"   # Node.js / Custom app
```

---

## Podman-Specific Features

### Pods (Podman-unique)

Run multiple services together:

```bash
# Create a pod with multiple containers
podman pod create --name hurd-dev -p 2222:22 -p 8080:80

# Run services in the pod
podman run --pod hurd-dev --name hurd-vm debian
podman run --pod hurd-dev --name hurd-ssh --entrypoint sleep infinity

# Manage as group
podman pod ps
podman pod stop hurd-dev
podman pod rm hurd-dev
```

### SELinux Support

If using SELinux:

```bash
# Add SELinux labels if needed
podman-compose down
# Modify docker-compose.yml to add:
# security_opt:
#   - label=disable
podman-compose up -d
```

### Network Modes

```bash
# Check network mode
podman network ls
podman inspect gnu-hurd-dev | grep -A 10 NetworkSettings

# Use host network (less isolated but simpler)
# In docker-compose.override.yml:
# network_mode: "host"
```

---

## Comparing Podman vs Docker vs Libvirt

For different use cases:

| Use Case | Recommended |
|----------|-------------|
| Development | **Podman** (quick, rootless) |
| CI/CD Pipelines | **Docker** (ubiquitous in CI) |
| Long-running servers | **Libvirt** (VMs better for servers) |
| Learning | **Podman** (simplest to start) |
| Production | **Docker** or **Libvirt** (established) |

---

## Advanced: Daemon Mode (Optional)

If you prefer Docker daemon-like behavior:

```bash
# Start Podman service
systemctl --user enable --now podman.socket
# Or system-wide:
# sudo systemctl enable --now podman.socket

# Then use normally
podman-compose up -d
```

---

## Next Steps

1. **[COMPLETE PHASE 1-3]**: Installation and basic usage ✓
2. **[PHASE 4]**: Understand compose files (docker-compose.yml)
3. **[PHASE 5]**: Customize for your workflow (docker-compose.override.yml)
4. **[PHASE 6]**: Advanced usage (pods, networking, volumes)
5. **[PHASE 7]**: Integration with your projects

---

## Resources

- Official Podman docs: https://podman.io/
- Podman Compose: https://github.com/containers/podman-compose
- Project guides:
  - `docs/01-GETTING-STARTED/QUICKSTART.md` - Quick reference
  - `docs/05-CI-CD/COMPOSE-VARIANTS.md` - Compare all backends
  - `docs/06-TROUBLESHOOTING/PLAYBOOK.md` - Problem solving

---

## Summary

**Podman is the recommended workflow** for GNU/Hurd development because:

✓ Rootless by default (better security)
✓ No daemon overhead (lower resource usage)
✓ Docker-compatible syntax (learn once, use everywhere)
✓ KVM auto-detected (no complex permission setup)
✓ Perfect for development and testing

**Quick command reference**:
```bash
# Download image once
./scripts/download-image.sh

# Start development
podman-compose -f docker-compose.yml -f docker-compose.kvm.yml up -d

# Access
ssh -p 2222 root@localhost

# Stop when done
podman-compose down
```

Happy hacking with GNU/Hurd and Podman! 🎉

---

**Last Updated**: 2026-01-15
**Status**: Production-ready
**Maintenance**: Community-supported
