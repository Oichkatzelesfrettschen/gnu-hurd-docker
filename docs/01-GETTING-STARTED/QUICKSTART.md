# GNU/Hurd Docker - Quick Start Guide

**Status**: Quickstart (see git history for updates)
**Consolidated From**:
- QUICKSTART.md (2025-11-06, i386-focused with GUI and custom features)
- QUICKSTART-CI-SETUP.md (CI-focused)
- SIMPLE-START.md (Docker pull method)
- Original QUICKSTART.md in 01-GETTING-STARTED (2025-11-07, x86_64-focused)

**Purpose**: Get Debian GNU/Hurd running in under 10 minutes

**Scope**: x86_64 guest only. Legacy i386 material (if any) is archived.

---

## Method 1: Docker Pull (Fastest - 3 Commands)

**Best for**: Quick testing, trying Hurd without cloning repository

```bash
# 1. Pull pre-built image
docker pull ghcr.io/oichkatzelesfrettschen/gnu-hurd-docker:latest

# 2. Run it (will download the disk image on first boot if enabled)
mkdir -p images

docker run -d \
  --name gnu-hurd-dev \
  -p 2222:2222 -p 5555:5555 -p 8080:8080 \
  -v "$(pwd)/images:/opt/hurd-image:rw" \
  -e AUTO_DOWNLOAD_IMAGE=1 \
  ghcr.io/oichkatzelesfrettschen/gnu-hurd-docker:latest

# Optional (Linux x86_64 only): add KVM for faster boot
#   --device /dev/kvm:/dev/kvm:rw
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

# 2. Download Hurd image to ./images (for bind-mount mode)
./scripts/setup-hurd-amd64.sh

# 3. Build and start
docker compose build
make up

# 4. Monitor boot (optional)
make logs
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
gnu-hurd-docker download  # Download Hurd image
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

**Via VNC/noVNC (recommended for first boot):**
```bash
make up-vnc
vncviewer localhost:5900
# Or open: http://localhost:6080/vnc.html
```

### Verify Architecture

```bash
# Inside guest
uname -m
# Expected: x86_64

uname -a
# Expected: GNU/Hurd ... x86_64
```

---

## GUI Setup (If Desktop Packages Installed)

### Starting XFCE Desktop

**Method 1: Simple (Recommended)**
```bash
startxfce4
```

**Method 2: Using xinit**
```bash
xinit /usr/bin/startxfce4 -- :0
```

**Method 3: Custom .xinitrc**
```bash
echo "exec startxfce4" > ~/.xinitrc
chmod +x ~/.xinitrc
startx
```

### GUI Components Available
- XFCE4 desktop environment
- firefox-esr, gimp, geany (if installed)
- xfce4-terminal, mousepad, thunar
- GUI applications via VNC

---

## File Sharing (Host ↔ Guest)

### 9p Filesystem Mount

Share files between host and guest:

```bash
# On host machine:
cp myfile.txt share/

# Inside Hurd VM:
mkdir -p /mnt/host
mount -t 9p -o trans=virtio hostshare /mnt/host
ls /mnt/host
cat /mnt/host/myfile.txt
```

### 9p Mount Details
```
Tag: hostshare
Host Path: ./share/ (mounted into container as /share)
Guest Mount: /mnt/host
Protocol: 9p over virtio
```

### Making Mount Permanent
```bash
# Inside guest
echo "hostshare /mnt/host 9p trans=virtio,version=9p2000.L 0 0" >> /etc/fstab
```

---

## System Credentials and Ports

### Default Credentials
```
Username: root
Password: root (or empty - varies by Debian release)
```

### Port Mappings
```
SSH:     localhost:2222 -> guest:22
HTTP:    localhost:8080 -> guest:80
Serial:  telnet localhost:5555
Monitor: telnet localhost:9999
VNC:     localhost:5900 (when using up-vnc)
noVNC:   http://localhost:6080/vnc.html (when using up-vnc)
```

---

## Current Configurations

### x86_64 Configuration (Primary)
```yaml
Architecture: x86_64
System:       Debian GNU/Hurd (ports/13.0, hurd-amd64)
CPU:          qemu64 or host (with KVM)
RAM:          4 GB (default, configurable)
SMP:          2 cores (configurable; higher counts may be unstable)
Acceleration: KVM (Linux) or TCG (macOS/Windows)
Disk:         IDE interface (Hurd-compatible)
Network:      e1000 NIC (Hurd-compatible)
Display:      nographic (default) or VNC
```

## Post-Installation Setup

### File Sharing (Host ↔ Guest)

- **Host ↔ Container**: `./share` is mounted to `/share` inside the container.
- **Host ↔ Guest (recommended)**: use SSH/SCP once SSH is up.
- **Host ↔ Guest (experimental)**: enable QEMU 9p by setting `ENABLE_9P=1` (see troubleshooting if mount fails).

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

### Install SSH Server (If Not Present)
```bash
apt-get install openssh-server random-egd
systemctl enable ssh
systemctl start ssh

# Test from host:
ssh -p 2222 root@localhost
```

### Create Snapshot
```bash
# On host
./scripts/manage-snapshots.sh create initial-setup
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

---

## Troubleshooting

### Container Won't Start

```bash
# Check Docker is running
docker ps

# Check logs
docker compose logs

# Check disk space
df -h .
# Need at least 10 GB free
```

### SSH Connection Refused

```bash
# Wait longer - boot takes 5-10 minutes
docker compose logs -f | grep -i ssh

# Check via serial console
telnet localhost 5555

# Manually start SSH inside guest
service ssh start
```

### GUI Won't Start

```bash
# Check X11 installed
which startx xinit

# Check XFCE installed
which startxfce4

# Try manual X start
startx -- :0
```

### 9p Mount Not Working

```bash
# Manual mount
mount -t 9p -o trans=virtio hostshare /mnt/host

# Check QEMU config
docker compose logs | grep virtfs

# Verify fstab entry
cat /etc/fstab | grep 9p
```

### Slow Boot / Performance

```bash
# Enable KVM acceleration (Linux x86_64 only)
make up-kvm

# Increase resources
# In docker-compose.yml:
environment:
  QEMU_RAM: 8192  # More RAM
  QEMU_SMP: 4     # More CPUs
```

### VNC Not Connecting

```bash
# Check QEMU is running
docker compose ps

# Check VNC port is open
ss -tlnp | grep 5900

# Restart container
docker compose restart
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

## Architecture Notes

### Supported platforms

- Guest: x86_64 only (runs inside QEMU)
- Container: `linux/amd64` and `linux/arm64`
- Acceleration: KVM only on Linux x86_64 hosts; other hosts use TCG emulation

---

## Official Documentation Links

- GNU Hurd: https://www.gnu.org/software/hurd/
- Debian Hurd: https://www.debian.org/ports/hurd/
- FAQ: https://www.gnu.org/software/hurd/faq.html

### Container Management

```bash
# View container logs
docker compose logs -f

# Stop container
docker compose down

# Restart container
docker compose restart

# Remove container and image
docker compose down -v
docker rmi gnu-hurd-docker
```

---

**Ready to go! Enjoy GNU/Hurd development!**

---

**Status**: Development/experimental
**Last Updated**: 2025-11-08
**Maintainer**: Oichkatzelesfrettschen
**Architecture**: x86_64 guest only
