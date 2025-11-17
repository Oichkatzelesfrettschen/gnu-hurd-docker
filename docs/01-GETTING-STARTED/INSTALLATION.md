# GNU/Hurd Docker - Complete Installation Guide

**Last Updated**: 2025-11-07
**Consolidated From**:
- INSTALLATION.md (2025-11-06)
- INSTALLATION-COMPLETE-GUIDE.md (2025-11-06)
- MANUAL-SETUP-REQUIRED.md (2025-11-05)
- requirements.md (2025-11-06)

**Purpose**: Complete guide for installing and setting up the Debian GNU/Hurd x86_64 QEMU development environment

**Scope**: Debian GNU/Hurd x86_64 only (i386 deprecated 2025-11-07)

**Status**: Production Ready

---

## Table of Contents

1. [System Requirements](#system-requirements)
2. [Quick Start](#quick-start)
3. [Platform Installation](#platform-installation)
4. [Docker Setup](#docker-setup)
5. [Hurd Image Download](#hurd-image-download)
6. [First Boot and Initial Access](#first-boot-and-initial-access)
7. [Post-Installation Setup](#post-installation-setup)
8. [Verification](#verification)
9. [Troubleshooting](#troubleshooting)
10. [Next Steps](#next-steps)

---

## System Requirements

### Minimum Configuration

| Component | Requirement | Notes |
|-----------|-------------|-------|
| **CPU** | 2 cores (x86_64) | Any modern 64-bit processor |
| **RAM** | 4 GB total | 4 GB for QEMU + overhead |
| **Disk** | 10 GB free | For Docker images and QCOW2 |
| **OS** | Linux, macOS, Windows | With Docker support |

### Recommended Configuration

| Component | Requirement | Notes |
|-----------|-------------|-------|
| **CPU** | 4+ cores with VT-x/AMD-V | For KVM acceleration (Linux only) |
| **RAM** | 8 GB total | Better performance, 4GB for VM |
| **Disk** | 20 GB free SSD | Faster I/O for QEMU |
| **OS** | Linux with KVM | Best performance |

### Software Dependencies

**Required on all platforms:**
- Docker Engine >= 20.10
- Docker Compose >= 1.29 (or Docker Compose V2)
- Git >= 2.30
- 10 GB free disk space
- Internet connection (for image downloads)

**Optional but recommended (Linux):**
- KVM support (`/dev/kvm` accessible)
- CPU with VT-x (Intel) or AMD-V (AMD)
- socat (for QMP/Monitor socket control)
- VNC client (for graphical console access)

---

## Usage Modes

This project supports two ways to run GNU/Hurd:

1. **Docker Mode** (Recommended): QEMU runs inside a container - simpler setup, better isolation
2. **Standalone QEMU Mode** (Advanced): QEMU runs directly on host - better performance, more control

See [USAGE-MODES.md](USAGE-MODES.md) for detailed comparison and decision guide.

For standalone QEMU setup, see [STANDALONE-QEMU.md](STANDALONE-QEMU.md).

## Quick Start

### Linux (Recommended)

```bash
# 1. Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
newgrp docker

# 2. Clone repository
git clone https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker.git
cd gnu-hurd-docker

# 3. Download Hurd x86_64 image
./scripts/download-image.sh

# 4. Build and start
docker-compose build
docker-compose up -d

# 5. View logs
docker-compose logs -f
```

### macOS

```bash
# 1. Install Docker Desktop
brew install --cask docker
# Start Docker Desktop from Applications

# 2. Clone repository
git clone https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker.git
cd gnu-hurd-docker

# 3. Continue with steps 3-5 from Linux instructions above
```

### Windows

```powershell
# 1. Install WSL 2
wsl --install

# 2. Install Docker Desktop (with WSL 2 backend)
# Download from https://www.docker.com/products/docker-desktop

# 3. Open WSL terminal and clone repository
git clone https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker.git
cd gnu-hurd-docker

# 4. Continue with steps 3-5 from Linux instructions above
```

---

## Platform Installation

### Linux Detailed Setup

#### Ubuntu / Debian

**1. Install Dependencies:**
```bash
# Update system
sudo apt-get update
sudo apt-get upgrade -y

# Install Docker
sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Install Git
sudo apt-get install -y git

# Add user to docker group
sudo usermod -aG docker $USER
```

**2. Enable KVM (Optional but Recommended):**
```bash
# Check CPU support
egrep -c '(vmx|svm)' /proc/cpuinfo
# Should return > 0

# Install KVM
sudo apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils

# Add user to kvm group
sudo usermod -aG kvm $USER

# Load KVM module
sudo modprobe kvm_intel  # or kvm_amd for AMD
```

**3. Configure Network (Fix Docker networking issues):**
```bash
# Load nf_tables modules
sudo modprobe nf_tables nf_tables_ipv4 nft_masq nf_nat

# Make permanent
cat <<EOF | sudo tee /etc/modules-load.d/docker.conf
nf_tables
nf_tables_ipv4
nft_masq
nf_nat
EOF

# Restart Docker
sudo systemctl restart docker
```

**4. Log out and log back in** for group changes to take effect.

**5. Verify Installation:**
```bash
# Check Docker
docker --version
docker ps

# Check KVM (if installed)
ls -l /dev/kvm
lsmod | grep kvm
```

#### Fedora / RHEL / CentOS

**1. Install Docker:**
```bash
# Add Docker repository
sudo dnf -y install dnf-plugins-core
sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo

# Install Docker
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Start and enable Docker
sudo systemctl enable --now docker

# Add user to docker group
sudo usermod -aG docker $USER
```

**2. Enable KVM:**
```bash
# Install KVM
sudo dnf install -y @virtualization

# Start libvirtd
sudo systemctl enable --now libvirtd

# Add user to groups
sudo usermod -aG kvm,libvirt $USER
```

**3. Configure SELinux (if enabled):**
```bash
# Allow Docker to use KVM
sudo setsebool -P virt_use_execmem 1
sudo setsebool -P container_manage_cgroup 1
```

#### Arch Linux

**Manual Installation:**
```bash
# Install Docker
sudo pacman -S docker docker-compose

# Start and enable Docker
sudo systemctl enable --now docker

# Add user to docker group
sudo usermod -aG docker $USER

# Install KVM (optional)
sudo pacman -S qemu-base libvirt
sudo systemctl enable --now libvirtd
sudo usermod -aG kvm,libvirt $USER
```

**AUR Package Installation:**
```bash
# Using yay
yay -S gnu-hurd-docker

# Using paru
paru -S gnu-hurd-docker

# Manual from AUR
git clone https://aur.archlinux.org/gnu-hurd-docker.git
cd gnu-hurd-docker
makepkg -si
```

After AUR installation, use the `gnu-hurd-docker` command:
```bash
gnu-hurd-docker download  # Download Debian GNU/Hurd x86_64 image
gnu-hurd-docker build     # Build Docker image
gnu-hurd-docker start     # Start environment
gnu-hurd-docker logs      # View logs
gnu-hurd-docker shell     # Access shell
gnu-hurd-docker stop      # Stop environment
```

### macOS Detailed Setup

**1. Install Homebrew (if not installed):**
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

**2. Install Docker Desktop:**
```bash
brew install --cask docker
```

**3. Start Docker Desktop:**
- Open Docker Desktop from Applications
- Wait for Docker to start (whale icon in menu bar)
- Configure resources (Preferences → Resources):
  - CPUs: 2 minimum, 4 recommended
  - Memory: 4 GB minimum, 8 GB recommended
  - Disk: 20 GB minimum

**4. Install Git:**
```bash
brew install git
```

**5. Clone and Setup:**
```bash
git clone https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker.git
cd gnu-hurd-docker
./scripts/download-image.sh
docker-compose build
docker-compose up -d
```

**Note:** macOS uses TCG emulation (no KVM). Expect slower performance but full functionality.

### Windows Detailed Setup

**1. Enable WSL 2:**
```powershell
# Run PowerShell as Administrator
wsl --install

# Or manually:
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart

# Reboot
shutdown /r /t 0

# Set WSL 2 as default
wsl --set-default-version 2
```

**2. Install Ubuntu in WSL:**
```powershell
wsl --install -d Ubuntu
```

**3. Install Docker Desktop:**
- Download from https://www.docker.com/products/docker-desktop
- Run installer
- Enable "Use WSL 2 based engine" in settings
- Enable integration with Ubuntu distribution

**4. Open WSL Terminal:**
```bash
# Update WSL Ubuntu
sudo apt-get update
sudo apt-get upgrade -y

# Install Git
sudo apt-get install -y git

# Clone repository
git clone https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker.git
cd gnu-hurd-docker

# Continue with standard Linux steps
./scripts/download-image.sh
docker-compose build
docker-compose up -d
```

**WSL Performance Tips:**
```powershell
# Create .wslconfig in Windows user directory (C:\Users\YourName\.wslconfig)
[wsl2]
memory=8GB
processors=4
swap=2GB
```

---

## Docker Setup

### Create Required Directories

```bash
mkdir -p qmp share logs images
```

### Configuration

Edit `docker-compose.yml` to customize:

```yaml
environment:
  # RAM allocation (in MB)
  QEMU_RAM: 4096          # Change to 8192 for more memory

  # CPU cores (Hurd 2025 has SMP support)
  QEMU_SMP: 2             # Change to 4 for more cores

  # Display mode
  ENABLE_VNC: 0           # Change to 1 for VNC access on port 5900

  # Serial port
  SERIAL_PORT: 5555       # Change if port conflicts
```

### Port Forwarding

Default ports:
- **2222:** SSH to guest (guest port 22)
- **8080:** HTTP to guest (guest port 80)
- **5555:** Serial console (telnet)
- **9999:** QEMU monitor (telnet)
- **5900:** VNC (if ENABLE_VNC=1)

To change ports, edit `docker-compose.yml`:
```yaml
ports:
  - "2222:2222"  # Change host port (left side)
  - "8080:8080"
```

### KVM Acceleration (Linux Only)

Enable KVM for better performance:

```yaml
# In docker-compose.yml
devices:
  - /dev/kvm:/dev/kvm:rw
```

Verify KVM works:
```bash
docker-compose logs | grep -i kvm
# Should show: "KVM acceleration detected"
```

---

## Hurd Image Download

### Automated Download (Recommended)

```bash
./scripts/download-image.sh
```

This script will:
- Download Debian GNU/Hurd x86_64 official image (~355 MB compressed)
- Extract to raw format
- Convert to QCOW2 format (~4.2 GB)
- Verify integrity

### Manual Download

```bash
# Download Debian GNU/Hurd 2025 "Trixie" (Debian 13, snapshot 2025-11-05)
wget http://cdimage.debian.org/cdimage/ports/13.0/hurd-amd64/debian-hurd.img.tar.xz

# Extract
tar xJf debian-hurd-amd64-20251105.img.tar.xz

# Convert to QCOW2 (for snapshot support)
qemu-img convert -f raw -O qcow2 -o preallocation=metadata debian-hurd-amd64-20251105.img debian-hurd-amd64.qcow2

# Move to images directory
mv debian-hurd-amd64.qcow2 images/
```

### Verify Image

```bash
# Check file format
qemu-img info images/debian-hurd-amd64.qcow2

# Expected output:
# file format: qcow2
# virtual size: 40 GiB
# disk size: ~4.2 GiB
```

---

## First Boot and Initial Access

### Start the Container

```bash
docker-compose build
docker-compose up -d
```

### Monitor Boot Process

**Via Logs:**
```bash
# Watch container logs
docker-compose logs -f

# Look for:
# - "Pure x86_64 Debian GNU/Hurd QEMU Environment"
# - "KVM acceleration detected" (Linux with KVM)
# - Boot progress messages
```

**Via Serial Console:**
```bash
telnet localhost 5555
# Or use the helper script
./scripts/connect-console.sh
```

**Via VNC (if enabled):**
```bash
# Install VNC client first
sudo pacman -S tigervnc  # Arch Linux
sudo apt-get install tigervnc-viewer  # Ubuntu/Debian
brew install tiger-vnc  # macOS

# Connect to VNC
vncviewer localhost:5900
```

### Wait for Boot (5-10 minutes)

**Expected boot times:**
- First boot: 5-10 minutes (filesystem initialization, x86_64 slower than i386)
- Subsequent boots: 2-5 minutes
- With KVM: 2-3 minutes
- Without KVM (TCG): 5-10 minutes

**Boot stages visible in logs:**
1. GRUB bootloader menu
2. GNU Mach kernel messages
3. Hurd bootstrap messages
4. Network configuration
5. Service startup
6. Login prompt

### First Login

**Default credentials:**
```
Username: root
Password: root (or empty - try pressing Enter)
```

**Via SSH (after boot completes):**
```bash
ssh -p 2222 root@localhost
# Default password: root
```

**Via Serial Console:**
```bash
telnet localhost 5555
# At login prompt:
# login: root
# Password: root
```

### Initial Configuration (Inside Guest)

```bash
# Set root password
passwd
# Enter new password twice

# Update package lists
apt-get update

# Set timezone (optional)
dpkg-reconfigure tzdata

# Check architecture
uname -m
# Expected: x86_64

# Verify network
ping -c 3 8.8.8.8

# Check available memory
free -h
```

---

## Post-Installation Setup

### Mount Shared Directory

The `share/` directory on the host is accessible inside the guest:

```bash
# Inside guest
mkdir -p /mnt/host
mount -t 9p -o trans=virtio scripts /mnt/host
cd /mnt/host

# Verify
ls -la
```

### Install Essential Tools

The repository includes installation scripts in `share/`:

**Option 1: Run All Installations**
```bash
# Inside guest, after mounting /mnt/host
cd /mnt/host
bash run-all-installations.sh
```

**Option 2: Run Individually**
```bash
# Essential tools first (required)
bash install-essentials-hurd.sh

# Node.js (optional)
bash install-nodejs-hurd.sh

# Claude Code (optional, may not work on Hurd)
bash install-claude-code-hurd.sh
```

### What Gets Installed

**Phase 1: Essential Tools (~1.5 GB)**
- **SSH Server**: openssh-server, random-egd (entropy generator)
- **Network Tools**: curl, wget, net-tools, dnsutils, telnet, netcat
- **Browsers**: lynx, w3m, links, elinks (text-based)
- **Development**: build-essential, git, vim, emacs-nox, python3, cmake
- **Hurd-Specific**: gnumach-dev, hurd-dev, mig (Mach Interface Generator)

**Custom Aliases Added:**
```bash
update          # apt-get update && apt-get upgrade
install         # apt-get install
search          # apt-cache search
web             # lynx (quick web browser)
myip            # curl -s ifconfig.me
ports           # ss -tulanp
pingtest        # ping -c 3 8.8.8.8
dnstest         # nslookup google.com
```

**Phase 2: Node.js (optional)**
- Node.js from Debian repos (v12-18) or build from source
- NPM with global configuration
- Version may be older but stable for Hurd

**Phase 3: Claude Code (optional)**
- Likely won't work (no official Hurd support)
- Use Claude Code from host machine instead

### Create Standard User (Optional)

```bash
# Inside guest
adduser developer
usermod -aG sudo developer

# Switch to new user
su - developer
```

### Configure Git

```bash
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
```

---

## Verification

### Check Container Status

```bash
# On host
docker-compose ps
# Should show: hurd-x86_64-qemu running

# Check QEMU process
docker-compose exec hurd-x86_64-qemu ps aux | grep qemu-system-x86_64
```

### Verify Network Access

**From host:**
```bash
# Test SSH port
nc -zv localhost 2222

# Test serial console
nc -zv localhost 5555
```

**Inside guest:**
```bash
ssh -p 2222 root@localhost << 'EOF'
  ping -c 3 8.8.8.8
  curl -I https://www.debian.org
EOF
```

### Check Architecture

```bash
# Inside guest
uname -m
# Expected: x86_64

# Verify QEMU binary
docker-compose exec hurd-x86_64-qemu which qemu-system-x86_64
# Expected: /usr/bin/qemu-system-x86_64
```

### Run System Test

```bash
# Execute comprehensive test inside guest
ssh -p 2222 root@localhost << 'EOF'
  uname -a
  free -h
  df -h
  apt-get --version
  dpkg -l | grep -E "gnumach-dev|hurd-dev|mig"
EOF
```

---

## Troubleshooting

### Container Won't Start

**Check Docker:**
```bash
docker ps
docker-compose ps
docker-compose logs
```

**Check Disk Space:**
```bash
df -h .
# Need at least 10 GB free
```

**Check Port Conflicts:**
```bash
netstat -tlnp | grep -E '2222|5555|8080'
# If ports are in use, change them in docker-compose.yml
```

### QEMU Won't Boot

**Check Image:**
```bash
ls -lh images/debian-hurd-amd64*.qcow2
# Should be ~4-5 GB

qemu-img check images/debian-hurd-amd64*.qcow2
# Should show: "No errors"
```

**Check Logs:**
```bash
docker-compose logs | tail -50
# Look for errors
```

**Check Resources:**
```bash
free -h
# Need at least 4 GB free RAM
```

### Can't Connect via SSH

**Wait for Full Boot:**
```bash
# Boot takes 5-10 minutes for x86_64
docker-compose logs -f | grep -i "ssh\|login"
```

**Check SSH is Running (inside guest):**
```bash
# Via serial console
telnet localhost 5555
# Then inside guest:
service ssh status
service ssh start
```

**Check Port Forwarding:**
```bash
docker-compose ps
# Verify 2222:2222 mapping
```

**Test Connection:**
```bash
ssh -v -p 2222 root@localhost
# Shows detailed connection attempt
```

### Serial Console Shows No Output

**Solution:**
- Press Enter several times to wake up the console
- Or use VNC instead: `vncviewer localhost:5900` (if ENABLE_VNC=1)
- Check if boot is still in progress (can take 10+ minutes on first boot)

### 9p Mount Fails

**Diagnosis:**
```bash
# Check if virtfs is configured in QEMU
docker-compose exec hurd-x86_64-qemu ps aux | grep virtfs
# Should see: -virtfs local,path=/share,mount_tag=scripts,...
```

**Solution:**
- Verify `share/` directory exists on host
- Restart container: `docker-compose restart`

### Package Installation Fails

**Diagnosis:**
```bash
# Inside guest
ping -c 3 8.8.8.8  # Test network
ping -c 3 google.com  # Test DNS
cat /etc/apt/sources.list  # Check apt sources
```

**Solution:**
```bash
# If network is down, restart DHCP (inside guest)
dhclient eth0

# Update package lists
apt-get update

# Retry installation
apt-get install -y gnumach-dev hurd-dev mig
```

### Slow Performance

**Enable KVM (Linux):**
```yaml
# In docker-compose.yml
devices:
  - /dev/kvm:/dev/kvm:rw
```

**Increase Resources:**
```yaml
environment:
  QEMU_RAM: 8192  # More RAM
  QEMU_SMP: 4     # More CPUs
```

**Check Host System:**
```bash
# CPU load
top

# Memory
free -h

# Disk I/O
iostat -x 1
```

### First Boot Taking Too Long

**Expected Behavior:**
- x86_64 Hurd is slower than i386 (less optimized port)
- First boot: 5-15 minutes (filesystem initialization)
- Subsequent boots: 2-5 minutes with KVM, 5-10 without

**Monitor Progress:**
```bash
# Watch VNC console
vncviewer localhost:5900

# Or serial console
telnet localhost 5555

# Check QEMU is running
docker-compose exec hurd-x86_64-qemu ps aux | grep qemu
```

---

## Next Steps

### After Successful Installation

1. **Explore the System:**
   ```bash
   ssh -p 2222 root@localhost
   # Try: ls, uname -a, apt-cache search <package>
   ```

2. **Install Development Tools:**
   ```bash
   ssh -p 2222 root@localhost << 'EOF'
     apt-get update
     apt-get install -y build-essential git vim
     apt-get install -y gnumach-dev hurd-dev mig
   EOF
   ```

3. **Create Snapshots:**
   ```bash
   ./scripts/manage-snapshots.sh create initial-setup
   ```

4. **Read Documentation:**
   - Architecture: `docs/02-ARCHITECTURE/SYSTEM-DESIGN.md`
   - Configuration: `docs/03-CONFIGURATION/`
   - Troubleshooting: `docs/06-TROUBLESHOOTING/`

5. **Join Community:**
   - Star the repository
   - Report bugs or suggest features
   - Contribute improvements

---

## Getting Help

### Documentation

- **README.md**: Overview and quick start
- **docs/01-GETTING-STARTED/QUICKSTART.md**: Fast 5-minute setup
- **docs/02-ARCHITECTURE/**: Design and rationale
- **docs/05-CI-CD/**: Automation and CI/CD
- **docs/06-TROUBLESHOOTING/**: Comprehensive issue resolution

### Support Channels

- **GitHub Issues**: https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker/issues
- **GitHub Discussions**: https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker/discussions
- **Documentation**: https://oichkatzelesfrettschen.github.io/gnu-hurd-docker

### Logs for Support

When reporting issues, include:

```bash
# System info
uname -a
docker --version
docker-compose --version

# Container logs
docker-compose logs > logs.txt

# System resources
free -h
df -h

# Check architecture inside guest
ssh -p 2222 root@localhost 'uname -m'
```

---

## References

- **GNU/Hurd**: https://www.gnu.org/software/hurd/
- **Debian GNU/Hurd**: https://www.debian.org/ports/hurd/
- **Debian Hurd 2025 "Trixie"**: http://cdimage.debian.org/cdimage/ports/13.0/hurd-amd64/
- **QEMU Documentation**: https://www.qemu.org/documentation/
- **Docker Documentation**: https://docs.docker.com/
- **Hurd Cloud Guide**: https://www.gnu.org/software/hurd/hurd/running/cloud.html

---

**Installation Complete! Enjoy GNU/Hurd x86_64 development!**

---

**Status**: Complete and Validated (x86_64-only)
**Last Updated**: 2025-11-07
**Maintainer**: Oichkatzelesfrettschen
**Architecture**: Pure x86_64 (i386 deprecated)
