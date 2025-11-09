# GNU/Hurd Docker - Quick Start Guide

**Last Updated**: 2025-11-08
**Consolidated From**:
- QUICKSTART.md (2025-11-06, i386-focused with GUI and custom features)
- QUICKSTART-CI-SETUP.md (CI-focused)
- SIMPLE-START.md (Docker pull method)
- Original QUICKSTART.md in 01-GETTING-STARTED (2025-11-07, x86_64-focused)

**Purpose**: Get Debian GNU/Hurd running in under 10 minutes

**Scope**: Primary focus on x86_64 (future direction), with i386 legacy support notes

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

# 2. Download Hurd image
./scripts/download-image.sh  # Automatically detects x86_64 or i386

# 3. Build and start
docker compose build
docker compose up -d

# 4. Monitor boot (optional)
docker compose logs -f
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

**Via VNC (if ENABLE_VNC=1 in docker-compose.yml):**
```bash
# Install VNC client first
vncviewer localhost:5900  # or port 5901 for i386 images
```

### Verify Architecture

```bash
# Inside guest
uname -m
# Expected: x86_64 (or i586 for i386 images)

uname -a
# Expected: GNU/Hurd ... x86_64 (or GNU ... i586)
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

## Custom Shell Features (i386 Images)

After login on i386 images, these custom commands are available:

### System Information Commands
```bash
mach-sysinfo          # Complete Hurd system info
mach-info             # CPU and kernel info
mach-memory           # Memory usage
mig-version           # MIG (Mach Interface Generator) version
```

### Development Shortcuts
```bash
mach-rebuild          # Auto-detect and rebuild project
cmake-debug           # Configure cmake in debug mode
cmake-release         # Configure cmake in release mode
configure-debug       # Configure autotools in debug
configure-release     # Configure autotools in release
```

### Git Shortcuts
```bash
gs                    # git status
ga                    # git add
gc                    # git commit
gp                    # git push
gl                    # git log --oneline --graph
gd                    # git diff
```

### File Operations
```bash
ll                    # ls -lahF --color
la                    # ls -AF --color
```

### Safety Features
```bash
rm, cp, mv            # All ask for confirmation (interactive)
```

---

## File Sharing (Host ↔ Guest)

### 9p Filesystem Mount

Share files between host and guest:

```bash
# On host machine:
cp myfile.txt share/

# Inside Hurd VM:
mkdir -p /mnt/host
mount -t 9p -o trans=virtio scripts /mnt/host
ls /mnt/host
cat /mnt/host/myfile.txt
```

### 9p Mount Details
```
Tag: scripts
Host Path: ./share/
Guest Mount: /mnt/host
Protocol: 9p over virtio
```

### Making Mount Permanent
```bash
# Inside guest
echo "scripts /mnt/host 9p trans=virtio,version=9p2000.L 0 0" >> /etc/fstab
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
Custom:  localhost:9999 -> guest:9999
Serial:  telnet localhost:5555
Monitor: telnet localhost:9999
VNC:     localhost:5900 (x86_64) or :5901 (i386)
```

---

## Current Configurations

### x86_64 Configuration (Primary)
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

### i386 Configuration (Legacy/80GB Image)
```yaml
Image:        debian-hurd-i386-80gb.qcow2 (80GB virtual, ~2.4GB actual)
System:       Debian GNU/Hurd 13 i386
CPU:          Pentium 3 (1 core for stability)
RAM:          4 GB
Acceleration: KVM (if available)
Display:      VNC on port 5901
Features:     Pre-installed GUI, development tools, custom shell
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
# Expected: x86_64 (or i586 for i386)

# Check development tools
which gcc g++ make cmake git

# Check MIG (Mach Interface Generator)
which mig
# Expected: /usr/bin/mig

# Test custom functions (i386 images)
type mach-rebuild mach-sysinfo

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

**Note**: x86_64 is slower than i386 (less optimized Hurd port), but it's the future direction.

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

### Shell Customizations Not Loading (i386)

```bash
# Reload .bashrc
source ~/.bashrc

# Verify customizations present
grep "Mach development" ~/.bashrc
```

### 9p Mount Not Working

```bash
# Manual mount
mount -t 9p -o trans=virtio scripts /mnt/host

# Check QEMU config
docker compose logs | grep virtfs

# Verify fstab entry
cat /etc/fstab | grep 9p
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

### VNC Not Connecting

```bash
# Check QEMU is running
docker compose ps

# Check VNC port is open
ss -tlnp | grep 590[01]

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

### Why x86_64 Primary?

As of 2025-11-07, this repository focuses primarily on x86_64:

**Reasons:**
- Debian GNU/Hurd 2025 officially supports x86_64 (hurd-amd64)
- x86_64 is the future of Hurd development
- Cleaner architecture (no multi-arch complexity)
- Better alignment with modern hardware

**Trade-offs:**
- Slower boot/performance than i386 (less optimized)
- Higher memory usage
- Some packages may have fewer optimizations

### i386 Support (Legacy)

The 80GB pre-configured i386 image remains available for:
- Users needing maximum performance
- Testing i386-specific code
- Educational purposes
- Legacy compatibility

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

**Status**: Production Ready
**Last Updated**: 2025-11-08
**Maintainer**: Oichkatzelesfrettschen
**Architecture**: x86_64 primary, i386 legacy support