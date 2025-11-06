# GNU/Hurd Docker - Quick Reference

**Last Updated:** 2025-11-06  
**Docker Image:** `ghcr.io/oichkatzelesfrettschen/gnu-hurd-docker`

---

## 🚀 Quick Start (1 Minute)

```bash
# Pull pre-built image
docker pull ghcr.io/oichkatzelesfrettschen/gnu-hurd-docker:latest

# Download Debian GNU/Hurd image (first time only, ~1-2 GB)
wget https://cdimage.debian.org/cdimage/ports/latest/hurd-i386/debian-hurd.img.tar.xz
tar xf debian-hurd.img.tar.xz

# Run container
docker run -d --privileged --name gnu-hurd \
  -p 2222:2222 -p 5555:5555 -p 5901:5901 \
  -v $(pwd):/opt/hurd-image \
  --device /dev/kvm \
  -e QEMU_RAM=4096 -e QEMU_SMP=4 -e DISPLAY_MODE=vnc \
  ghcr.io/oichkatzelesfrettschen/gnu-hurd-docker:latest

# Access (wait ~60 seconds for boot)
ssh -p 2222 root@localhost  # Password: root
```

---

## 📦 Installation Methods

### Method 1: Pre-built Docker Image (Recommended)

**Fastest**: No build required, just pull and run.

```bash
docker pull ghcr.io/oichkatzelesfrettschen/gnu-hurd-docker:latest
```

### Method 2: Release Archive

**Offline-friendly**: Download complete package with scripts and docs.

```bash
# Download latest release
wget https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker/releases/latest/download/gnu-hurd-docker-1.0.0.tar.gz
tar xzf gnu-hurd-docker-1.0.0.tar.gz
cd gnu-hurd-docker-1.0.0

# Download Hurd image and run
./scripts/download-image.sh
docker-compose up -d
```

### Method 3: Build from Source

**Most flexible**: Customize and modify as needed.

```bash
git clone https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker.git
cd gnu-hurd-docker
./scripts/download-image.sh
docker-compose build
docker-compose up -d
```

### Method 4: Arch Linux AUR

**Arch users**: Native package management.

```bash
yay -S gnu-hurd-docker
# or
paru -S gnu-hurd-docker
```

---

## 🎛️ Configuration Options

### Display Modes

```bash
# Headless (serial console only)
-e DISPLAY_MODE=nographic

# VNC (remote access)
-e DISPLAY_MODE=vnc

# SDL with OpenGL (local GUI, best performance)
-e DISPLAY_MODE=sdl-gl

# GTK with OpenGL (rich GUI features)
-e DISPLAY_MODE=gtk-gl
```

### Resource Allocation

```bash
# Memory (MB)
-e QEMU_RAM=2048    # Minimum (CLI)
-e QEMU_RAM=4096    # Recommended (CLI + GUI)
-e QEMU_RAM=8192    # Development workstation

# CPU cores
-e QEMU_SMP=2       # Minimum
-e QEMU_SMP=4       # Recommended
-e QEMU_SMP=6       # High performance

# Storage type
-e QEMU_STORAGE=virtio    # Fast (recommended)
-e QEMU_STORAGE=ide       # Compatibility

# Network type
-e QEMU_NET=virtio        # Fast (recommended)
-e QEMU_NET=e1000         # Compatibility

# Video device
-e QEMU_VIDEO=virtio-vga-gl   # Best for GUI
-e QEMU_VIDEO=std             # Standard VGA
-e QEMU_VIDEO=cirrus          # Legacy compatibility
```

---

## 🔌 Port Mappings

| Host Port | Guest Port | Purpose |
|-----------|------------|---------|
| 2222 | 22 | SSH access |
| 5555 | - | Serial console (telnet) |
| 5901 | - | VNC display |
| 8080 | 80 | HTTP server |
| 9999 | 9999 | Custom application |

---

## 🔑 Access Methods

### SSH Access

```bash
# Root user
ssh -p 2222 root@localhost
# Password: root

# Agents user (sudo)
ssh -p 2222 agents@localhost
# Password: agents (change on first login)
```

### Serial Console

```bash
telnet localhost 5555
```

### VNC Display

```bash
# Using VNC client
vncviewer localhost:5901

# Or in browser (with VNC web client)
# Connect to: localhost:5901
```

---

## 🛠️ Common Commands

### Container Management

```bash
# Start container
docker start gnu-hurd

# Stop container
docker stop gnu-hurd

# Restart container
docker restart gnu-hurd

# View logs
docker logs -f gnu-hurd

# Remove container
docker rm -f gnu-hurd
```

### Using docker-compose

```bash
# Start
docker-compose up -d

# Stop
docker-compose down

# Restart
docker-compose restart

# View logs
docker-compose logs -f

# Rebuild
docker-compose build --no-cache
```

### Guest System

```bash
# SSH into guest
ssh -p 2222 root@localhost

# Inside guest:
# Check system info
uname -a

# Check Hurd servers
ps aux | grep -E "ext2fs|pfinet"

# Mount shared filesystem
mount -t 9p -o trans=virtio scripts /mnt

# Install packages
apt-get update
apt-get install build-essential

# Compile C program
gcc hello.c -o hello
./hello
```

---

## 📊 Performance Tips

### Maximum Performance Configuration

```bash
docker run -d --privileged --name gnu-hurd \
  -p 2222:2222 -p 5555:5555 -p 5901:5901 \
  -v $(pwd):/opt/hurd-image \
  --device /dev/kvm \
  -e QEMU_RAM=8192 \
  -e QEMU_SMP=6 \
  -e QEMU_STORAGE=virtio \
  -e QEMU_NET=virtio \
  -e QEMU_VIDEO=virtio-vga-gl \
  -e DISPLAY_MODE=sdl-gl \
  ghcr.io/oichkatzelesfrettschen/gnu-hurd-docker:latest
```

**Expected Performance:**
- Boot time: 30-60 seconds (with KVM)
- Disk I/O: 2-3x faster than IDE
- Network: 30-50% faster than E1000
- CPU: ~85% of native speed

---

## 🧪 Testing

### Run System Tests

```bash
# Download and run test script
wget https://raw.githubusercontent.com/Oichkatzelesfrettschen/gnu-hurd-docker/main/scripts/test-hurd-system.sh
chmod +x test-hurd-system.sh
./test-hurd-system.sh
```

**Tests include:**
- Container status
- Boot completion
- User authentication
- C compilation
- Package management
- Filesystem operations
- Hurd-specific features

---

## 📚 Documentation Links

### Essential Guides
- [Installation Guide](https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker/blob/main/INSTALLATION.md)
- [QEMU Optimization Guide](https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker/blob/main/docs/QEMU-OPTIMIZATION-2025.md)
- [Requirements](https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker/blob/main/requirements.md)

### Advanced Topics
- [CI/CD Guide](https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker/blob/main/docs/CI-CD-GUIDE.md)
- [Testing Report](https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker/blob/main/docs/HURD-TESTING-REPORT.md)
- [Architecture](https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker/blob/main/docs/ARCHITECTURE.md)

### Complete Index
- [Documentation Index](https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker/blob/main/docs/INDEX.md)

---

## ❓ Troubleshooting

### Container won't start

```bash
# Check if KVM is available
ls -l /dev/kvm

# If no KVM, remove --device flag
docker run -d --privileged --name gnu-hurd \
  -p 2222:2222 -p 5555:5555 \
  -v $(pwd):/opt/hurd-image \
  -e QEMU_RAM=2048 \
  ghcr.io/oichkatzelesfrettschen/gnu-hurd-docker:latest
```

### Can't connect via SSH

```bash
# Wait longer (boot can take 1-3 minutes)
# Check container logs
docker logs gnu-hurd

# Check if port 2222 is listening
nc -zv localhost 2222

# Connect to serial console
telnet localhost 5555
```

### Slow performance

```bash
# Enable KVM acceleration (Linux only)
--device /dev/kvm

# Use VirtIO devices
-e QEMU_STORAGE=virtio -e QEMU_NET=virtio

# Increase resources
-e QEMU_RAM=4096 -e QEMU_SMP=4
```

### No graphics display

```bash
# Check VNC
vncviewer localhost:5901

# Or use nographic mode
-e DISPLAY_MODE=nographic

# Connect via serial console
telnet localhost 5555
```

---

## 🔄 Updates

### Update to Latest Image

```bash
# Pull latest
docker pull ghcr.io/oichkatzelesfrettschen/gnu-hurd-docker:latest

# Stop old container
docker stop gnu-hurd
docker rm gnu-hurd

# Start with new image
docker run -d --privileged --name gnu-hurd \
  -p 2222:2222 -p 5555:5555 -p 5901:5901 \
  -v $(pwd):/opt/hurd-image \
  --device /dev/kvm \
  ghcr.io/oichkatzelesfrettschen/gnu-hurd-docker:latest
```

### Update Hurd Image

```bash
# Backup current image
cp debian-hurd-*.qcow2 debian-hurd-backup.qcow2

# Download new image
./scripts/download-image.sh

# Restart container
docker restart gnu-hurd
```

---

## 🆘 Support

- **GitHub Issues**: https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker/issues
- **Documentation**: https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker
- **Docker Hub**: https://ghcr.io/oichkatzelesfrettschen/gnu-hurd-docker

---

**Version:** 1.0  
**Status:** Production Ready  
**License:** MIT
