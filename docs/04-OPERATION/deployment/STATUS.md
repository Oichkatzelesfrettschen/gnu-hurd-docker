# Docker Compose GNU/Mach - Deployment Status

**Date:** 2025-11-05  
**Status:** Ready for Docker Build and Deploy  
**Files Created:** Dockerfile, entrypoint.sh, docker-compose.yml  

---

## Summary

All Docker Compose configuration files for native i386 GNU/Mach containerization have been successfully created. The architecture implements a QEMU-in-Docker pattern that runs the complete GNU/Mach microkernel environment inside a privileged Docker container with bind-mounted QCOW2 disk image.

---

## Files Structure

```
GNUHurd2025/
├── debian-hurd-i386-20251105.qcow2    (2.1 GB - QEMU disk image)
├── debian-hurd-i386-20251105.img       (4.2 GB - raw disk image)
├── debian-hurd.img.tar.xz              (355 MB - source archive)
├── Dockerfile                          (Docker image specification)
├── entrypoint.sh                       (QEMU launcher script)
├── docker-compose.yml                  (Container orchestration)
├── DOCKER-ARCHITECTURE-DESIGN.md       (Architecture documentation)
└── DEPLOYMENT-STATUS.md                (This file)
```

---

## Deployment Procedure

### Prerequisites

```bash
# Verify Docker is installed and running
docker --version
docker-compose --version

# Add current user to docker group (one-time)
sudo usermod -a -G docker $USER
newgrp docker

# Verify QCOW2 image exists
ls -lh debian-hurd-i386-20251105.qcow2
```

### Build Docker Image

```bash
cd /home/eirikr/GNUHurd2025

# Build the Docker image
docker-compose build

# Expected output: Successfully tagged gnu-hurd-dev:latest
```

### Deploy Container

```bash
# Start the container in background
docker-compose up -d

# Verify container is running
docker-compose ps

# Expected output: gnu-hurd-dev  Up  [status]
```

### Access GNU/Mach System

```bash
# View startup logs
docker-compose logs -f

# Access container shell
docker-compose exec gnu-hurd-dev bash

# Access serial console (PTY)
# Find PTY path from logs: "char device redirected to /dev/pts/X"
screen /dev/pts/X

# Send keystroke to GRUB menu (if needed)
# Press: Enter to select boot entry
```

### Network Access

```bash
# SSH access (port forwarded to 2222)
ssh -p 2222 root@localhost

# Custom port access (HTTP on 8080, etc.)
# Add port mappings to docker-compose.yml
```

### Stop/Restart Container

```bash
# Stop container
docker-compose stop

# Restart
docker-compose start

# Full shutdown and cleanup
docker-compose down
```

---

## Architecture Details

### Dockerfile

Builds a Debian Bookworm base image with:
- QEMU system i386 emulator (qemu-system-i386)
- QEMU utilities (qemu-utils)
- Networking tools (screen, telnet, curl)
- Entrypoint script for automatic QEMU launch

### entrypoint.sh

Bash script that:
1. Validates QCOW2 image exists at /opt/hurd-image/
2. Launches QEMU with optimized parameters:
   - CPU: Pentium (32-bit compatible)
   - RAM: 1.5 GB allocation
   - Storage: QCOW2 with writeback cache
   - Network: User-mode NAT with SSH port forwarding (22→2222)
   - Serial: PTY for interactive access
   - Debug: Logging to /tmp/qemu.log

### docker-compose.yml

YAML specification for container orchestration:
- Build context: Current directory (GNUHurd2025/)
- Privileged: true (required for QEMU emulation)
- Volume: Current directory → /opt/hurd-image (read-only)
- Ports: 2222 (SSH), 9999 (custom)
- TTY: Enabled for interactive session
- Network: Custom bridge network

---

## System Parameters

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| CPU Type | Pentium | 32-bit compatible, stable emulation |
| RAM | 1.5G | Adequate for GNU/Hurd boot and operation |
| Disk Format | QCOW2 | 50% space efficiency vs raw |
| Disk Cache | writeback | Optimized I/O performance |
| Network | user-mode | No root privilege required for networking |
| Serial | pty | Interactive TTY access |

---

## Known Limitations

1. **Kernel Module Drivers:** Cannot be loaded in containerized QEMU (no kernel source)
2. **Hardware Access:** Limited to QEMU-emulated devices
3. **Network Performance:** User-mode NAT adds ~5-10ms latency
4. **X11/GUI:** Not possible with -nographic mode

---

## Troubleshooting

### Container won't start
```bash
docker-compose logs --tail=50
# Check for: QCOW2 not found, permission denied, port conflicts
```

### QEMU hangs during boot
```bash
# Serial console might be waiting for GRUB input
# Send Enter key or keystroke via screen
screen /dev/pts/X
# Press: Enter
```

### Network connection issues
```bash
# Inside container, check QEMU is running
docker-compose exec gnu-hurd-dev ps aux | grep qemu

# Test SSH from host
ssh -p 2222 root@localhost
```

### Port conflicts
```bash
# Check for existing containers on port 2222/9999
docker ps
docker-compose down -v  # Remove and clean up
```

---

## Performance Notes

- **CPU emulation:** ~100-200ms latency expected (acceptable for development)
- **Disk I/O:** Writeback cache provides good throughput
- **Memory:** 1.5GB sufficient for GNU/Hurd base system
- **Boot time:** ~2-3 minutes typical (depends on CPU speed)

---

## Next Steps

1. Ensure Docker daemon is running: `sudo systemctl start docker`
2. Build image: `docker-compose build`
3. Deploy: `docker-compose up -d`
4. Verify boot: `docker-compose logs -f`
5. Access system: `docker-compose exec gnu-hurd-dev bash`

---

## Architecture Reference

For detailed architectural rationale and design decisions, see:
- **DOCKER-ARCHITECTURE-DESIGN.md** - Complete architecture documentation

For research background:
- **MACH_QEMU_RESEARCH_REPORT.md** - Thesis verification and research
- **QUICK_START_GUIDE.md** - Getting started with raw QEMU

---

**Status:** Configuration complete and ready for deployment  
**Action Required:** Build Docker image and launch container  

