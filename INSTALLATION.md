# GNU/Hurd Docker - Complete Installation Guide

**Last Updated:** 2025-11-06  
**Version:** 2.0  
**Audience:** All users (Linux, macOS, Windows)

---

## Table of Contents

1. [Quick Installation](#quick-installation)
2. [Platform-Specific Instructions](#platform-specific-instructions)
3. [Arch Linux (AUR)](#arch-linux-aur)
4. [Manual Installation](#manual-installation)
5. [Configuration](#configuration)
6. [First Run](#first-run)
7. [Verification](#verification)
8. [Troubleshooting](#troubleshooting)

---

## Quick Installation

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

# 3. Download Hurd image
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

## Platform-Specific Instructions

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

See [Arch Linux (AUR)](#arch-linux-aur) section below for package installation.

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

## Arch Linux (AUR)

### Installation from AUR

**Using yay:**
```bash
yay -S gnu-hurd-docker
```

**Using paru:**
```bash
paru -S gnu-hurd-docker
```

**Manual from AUR:**
```bash
git clone https://aur.archlinux.org/gnu-hurd-docker.git
cd gnu-hurd-docker
makepkg -si
```

### Package Usage

After installation, use the `gnu-hurd-docker` command:

```bash
# Download Debian GNU/Hurd image
gnu-hurd-docker download

# Build Docker image
gnu-hurd-docker build

# Start environment
gnu-hurd-docker start

# View logs
gnu-hurd-docker logs

# Access shell
gnu-hurd-docker shell

# Stop environment
gnu-hurd-docker stop

# Show status
gnu-hurd-docker status

# Help
gnu-hurd-docker help
```

**Work Directory:** `~/.local/share/gnu-hurd-docker/`

### Package Files

```
/opt/gnu-hurd-docker/          # Installation directory
/etc/gnu-hurd-docker/          # Configuration
/usr/bin/gnu-hurd-docker       # Launcher script
/usr/share/doc/gnu-hurd-docker/  # Documentation
```

---

## Manual Installation

### From Source (All Platforms)

**1. Prerequisites:**
- Docker Engine (>=20.10)
- Docker Compose (>=1.29)
- Git (>=2.30)
- 8 GB free disk space
- 2 GB available RAM

**2. Clone Repository:**
```bash
git clone https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker.git
cd gnu-hurd-docker
```

**3. Create Required Directories:**
```bash
mkdir -p qmp share logs
```

**4. Download Debian GNU/Hurd Image:**
```bash
./scripts/download-image.sh
```

This script will:
- Download Debian GNU/Hurd official image (~355 MB)
- Convert to QCOW2 format (~2.1 GB)
- Verify integrity

**Alternative Manual Download:**
```bash
# Download from Debian
wget https://cdimage.debian.org/cdimage/ports/latest/hurd-i386/debian-hurd-sid-i386.img.tar.gz

# Extract
tar xzf debian-hurd-sid-i386.img.tar.gz

# Convert to QCOW2
qemu-img convert -f raw -O qcow2 debian-hurd.img debian-hurd-i386.qcow2

# Move to expected location
mv debian-hurd-i386.qcow2 ./
```

**5. Build Docker Image:**
```bash
docker-compose build
```

**6. Start Container:**
```bash
docker-compose up -d
```

**7. Verify:**
```bash
docker-compose ps
docker-compose logs
```

---

## Configuration

### docker-compose.yml Customization

Edit `docker-compose.yml` to customize:

```yaml
environment:
  # RAM allocation (in MB)
  - QEMU_RAM=2048          # Change to 4096 for more memory
  
  # CPU cores
  - QEMU_SMP=1             # Change to 2 or 4 for more cores
  
  # Display mode
  - DISPLAY_MODE=nographic  # Change to 'vnc' for VNC access
  
  # Serial port
  - SERIAL_PORT=5555       # Change if port conflicts
```

### Port Forwarding

Default ports:
- **2222:** SSH to guest (guest port 22)
- **8080:** HTTP to guest (guest port 80)
- **5555:** Serial console (telnet)
- **9999:** Custom application port
- **5901:** VNC (if DISPLAY_MODE=vnc)

To change ports, edit `docker-compose.yml`:
```yaml
ports:
  - "2222:2222"  # Change host port (left side)
  - "8080:80"
```

### KVM Acceleration (Linux Only)

Enable KVM for better performance:

```yaml
# Uncomment in docker-compose.yml
devices:
  - /dev/kvm
```

Verify KVM works:
```bash
docker-compose logs | grep -i kvm
# Should show: "KVM acceleration: ENABLED"
```

### Shared Directory

Place files in `./share/` to access them in the guest:

**Inside guest:**
```bash
mkdir -p /mnt/scripts
mount -t 9p -o trans=virtio scripts /mnt/scripts
cd /mnt/scripts
# Your files from ./share/ are here
```

---

## First Run

### 1. Start the Container

```bash
docker-compose up -d
```

### 2. Monitor Boot Process

```bash
# Watch logs
docker-compose logs -f

# Look for:
# - "QEMU i386 Microkernel Environment"
# - "KVM acceleration: ENABLED" (Linux with KVM)
# - Boot progress messages
```

### 3. Wait for Boot (2-5 minutes)

**Via Logs:**
```bash
docker-compose logs -f | grep -i "login"
```

**Via Serial Console:**
```bash
telnet localhost 5555
# Or
./scripts/connect-console.sh
```

### 4. First Login

**Via SSH:**
```bash
ssh -p 2222 root@localhost
# Default password: root (Debian GNU/Hurd default)
```

**Via Serial Console:**
```bash
telnet localhost 5555
# At login prompt:
# login: root
# Password: root
```

### 5. Initial Setup (Inside Guest)

```bash
# Update package lists
apt-get update

# Set timezone (optional)
dpkg-reconfigure tzdata

# Change root password
passwd

# Create standard user
adduser myuser
usermod -aG sudo myuser

# Install development tools (optional)
apt-get install -y build-essential git
```

---

## Verification

### Check Container Status

```bash
docker-compose ps
# Should show: gnu-hurd-dev running
```

### Check QEMU Process

```bash
docker-compose exec gnu-hurd-dev ps aux | grep qemu
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
ssh -p 2222 root@localhost 'ping -c 3 8.8.8.8'
```

### Check KVM Acceleration (Linux)

```bash
docker-compose logs | grep -i "acceleration"
# Should show: "KVM acceleration: ENABLED"
```

### Run System Test

```bash
# Execute test inside guest
ssh -p 2222 root@localhost << 'EOF'
  uname -a
  free -h
  df -h
  apt-get --version
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
# Need at least 8 GB free
```

**Check Port Conflicts:**
```bash
netstat -tlnp | grep -E '2222|5555|8080'
# If ports are in use, change them in docker-compose.yml
```

### QEMU Won't Boot

**Check Image:**
```bash
ls -lh debian-hurd-i386*.qcow2
# Should be ~2-4 GB

qemu-img check debian-hurd-i386*.qcow2
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
# Need at least 2 GB free RAM
```

### Can't Connect via SSH

**Wait for Full Boot:**
```bash
# Boot takes 2-5 minutes
docker-compose logs -f | grep -i "ssh\|login"
```

**Check SSH is Running:**
```bash
docker-compose exec gnu-hurd-dev bash -c "ps aux | grep sshd"
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

### Slow Performance

**Enable KVM (Linux):**
```yaml
# In docker-compose.yml
devices:
  - /dev/kvm
```

**Increase Resources:**
```yaml
environment:
  - QEMU_RAM=4096  # More RAM
  - QEMU_SMP=2     # More CPUs
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

### Docker Networking Issues (Linux)

**Load Kernel Modules:**
```bash
sudo modprobe nf_tables nf_tables_ipv4 nft_masq nf_nat

# Make permanent
cat <<EOF | sudo tee /etc/modules-load.d/docker.conf
nf_tables
nf_tables_ipv4
nft_masq
nf_nat
EOF
```

**Restart Docker:**
```bash
sudo systemctl restart docker
```

**Verify:**
```bash
lsmod | grep nf_tables
docker ps
```

### Image Download Fails

**Manual Download:**
```bash
wget -c https://cdimage.debian.org/cdimage/ports/latest/hurd-i386/debian-hurd-sid-i386.img.tar.gz

# Or use aria2 for better reliability:
aria2c -x 16 -s 16 https://cdimage.debian.org/cdimage/ports/latest/hurd-i386/debian-hurd-sid-i386.img.tar.gz
```

**Convert Manually:**
```bash
tar xzf debian-hurd-sid-i386.img.tar.gz
qemu-img convert -f raw -O qcow2 -p debian-hurd.img debian-hurd-i386.qcow2
```

---

## Getting Help

### Documentation

- **README.md:** Overview and quick start
- **requirements.md:** Detailed system requirements
- **docs/ARCHITECTURE.md:** Design and rationale
- **docs/CI-CD-GUIDE.md:** Automation and CI/CD
- **docs/TROUBLESHOOTING.md:** Common issues

### Support Channels

- **GitHub Issues:** https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker/issues
- **GitHub Discussions:** https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker/discussions
- **Documentation:** https://oichkatzelesfrettschen.github.io/gnu-hurd-docker

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
```

---

## Next Steps

After successful installation:

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
   EOF
   ```

3. **Create Snapshots:**
   ```bash
   ./scripts/manage-snapshots.sh create initial-setup
   ```

4. **Read Documentation:**
   - Architecture: `docs/ARCHITECTURE.md`
   - CI/CD: `docs/CI-CD-GUIDE.md`
   - Advanced: `docs/QEMU-TUNING.md`

5. **Join Community:**
   - Star the repository
   - Report bugs or suggest features
   - Contribute improvements

---

**Installation Complete! Enjoy GNU/Hurd development! 🚀**

---

**Status:** Complete  
**Last Updated:** 2025-11-06  
**Maintainer:** Oichkatzelesfrettschen
