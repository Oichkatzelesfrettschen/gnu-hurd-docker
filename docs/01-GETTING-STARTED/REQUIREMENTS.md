# GNU/Hurd Docker - Installation Requirements

**Last Updated:** 2025-11-06  
**Version:** 2.0  
**Status:** Production Ready

---

## Table of Contents

1. [System Requirements](#system-requirements)
2. [Host Platform Requirements](#host-platform-requirements)
3. [Software Dependencies](#software-dependencies)
4. [Optional Dependencies](#optional-dependencies)
5. [Build Dependencies](#build-dependencies)
6. [Runtime Dependencies](#runtime-dependencies)
7. [Network Requirements](#network-requirements)
8. [Storage Requirements](#storage-requirements)

---

## System Requirements

### Minimum Configuration

| Component | Requirement | Notes |
|-----------|-------------|-------|
| **CPU** | 2 cores (x86_64) | Any modern 64-bit processor |
| **RAM** | 4 GB total | 2 GB for QEMU, 2 GB for host |
| **Disk** | 10 GB free | For Docker images and QCOW2 |
| **OS** | Linux, macOS, Windows | With Docker support |

### Recommended Configuration

| Component | Requirement | Notes |
|-----------|-------------|-------|
| **CPU** | 4+ cores with VT-x/AMD-V | For KVM acceleration (Linux only) |
| **RAM** | 8 GB total | For better performance |
| **Disk** | 20 GB free SSD | Faster I/O for QEMU |
| **OS** | Linux with KVM | Best performance |

---

## Host Platform Requirements

### Linux (Recommended)

**Distribution Requirements:**
- Any modern Linux distribution (kernel 5.10+)
- **Ubuntu/Debian:** 20.04 LTS or later
- **Fedora/RHEL:** 8 or later
- **Arch Linux:** Rolling release
- **openSUSE:** 15.3 or later

**Kernel Requirements:**
- `CONFIG_NETFILTER=y` - Network filtering support
- `CONFIG_NF_TABLES=y` - nf_tables support
- `CONFIG_NF_NAT=y` - NAT support
- `CONFIG_BRIDGE=m` - Bridge support (optional)
- `CONFIG_KVM=m` - KVM support (optional, for acceleration)
- `CONFIG_KVM_INTEL=m` or `CONFIG_KVM_AMD=m` - CPU-specific KVM

**Modules to Load:**
```bash
# Required for Docker
modprobe nf_tables
modprobe nf_tables_ipv4
modprobe nft_masq
modprobe nf_nat

# Optional for KVM
modprobe kvm
modprobe kvm_intel  # or kvm_amd for AMD CPUs
```

### macOS

**Version Requirements:**
- macOS 11 (Big Sur) or later
- Docker Desktop 4.0+

**Limitations:**
- No KVM acceleration (TCG mode only)
- Slower emulation performance
- User-mode networking only

**Installation:**
```bash
# Install Docker Desktop
brew install --cask docker

# Start Docker Desktop from Applications
```

### Windows

**Version Requirements:**
- Windows 10 Pro/Enterprise (build 19041+) or Windows 11
- WSL 2 enabled
- Docker Desktop 4.0+

**Prerequisites:**
```powershell
# Enable WSL 2
wsl --install

# Enable Hyper-V (Windows Pro/Enterprise)
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All
```

**Limitations:**
- No KVM acceleration (TCG mode only)
- Performance varies with WSL 2 configuration

---

## Software Dependencies

### Core Requirements (All Platforms)

#### 1. Docker Engine

**Version:** 20.10 or later

**Linux Installation:**
```bash
# Ubuntu/Debian
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Arch Linux
sudo pacman -S docker docker-compose
sudo systemctl enable --now docker
sudo usermod -aG docker $USER

# Fedora/RHEL
sudo dnf install docker docker-compose
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
```

**macOS Installation:**
```bash
brew install --cask docker
# Start Docker Desktop from Applications
```

**Windows Installation:**
- Download Docker Desktop from https://www.docker.com/products/docker-desktop
- Install with WSL 2 backend enabled

**Verification:**
```bash
docker --version
# Expected: Docker version 20.10.0 or later
```

#### 2. Docker Compose

**Version:** 1.29 or later (or Docker Compose V2)

**Linux Installation:**
```bash
# If not included with Docker
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Or use Docker Compose V2 (plugin)
# Already included with Docker Desktop and modern Docker Engine
```

**Verification:**
```bash
docker-compose --version
# Expected: docker-compose version 1.29.0 or later
# OR: Docker Compose version v2.x.x
```

#### 3. Git

**Version:** 2.30 or later

**Installation:**
```bash
# Linux (Ubuntu/Debian)
sudo apt-get install git

# Linux (Arch)
sudo pacman -S git

# macOS
brew install git

# Windows (via Git for Windows)
# Download from https://git-scm.com/download/win
```

**Verification:**
```bash
git --version
# Expected: git version 2.30.0 or later
```

---

## Optional Dependencies

### For KVM Acceleration (Linux Only)

**Required:**
- KVM kernel modules loaded
- `/dev/kvm` device accessible
- CPU with VT-x (Intel) or AMD-V (AMD) support

**Installation:**
```bash
# Ubuntu/Debian
sudo apt-get install qemu-kvm libvirt-daemon-system

# Arch Linux
sudo pacman -S qemu-base libvirt

# Fedora/RHEL
sudo dnf install qemu-kvm libvirt
```

**Verification:**
```bash
# Check if KVM is available
ls -l /dev/kvm
# Expected: crw-rw---- 1 root kvm ... /dev/kvm

# Check CPU virtualization support
egrep -c '(vmx|svm)' /proc/cpuinfo
# Expected: > 0

# Verify KVM module loaded
lsmod | grep kvm
# Expected: kvm_intel or kvm_amd
```

### For Development and Testing

#### ShellCheck (Script Validation)

**Installation:**
```bash
# Ubuntu/Debian
sudo apt-get install shellcheck

# Arch Linux
sudo pacman -S shellcheck

# macOS
brew install shellcheck
```

**Version:** 0.8.0 or later

#### Python 3 (for YAML validation and QMP scripts)

**Installation:**
```bash
# Ubuntu/Debian
sudo apt-get install python3 python3-pip

# Arch Linux
sudo pacman -S python python-pip

# macOS
brew install python3
```

**Version:** 3.7 or later

**Python Packages:**
```bash
pip3 install pyyaml jsonschema
```

#### YAML Lint

**Installation:**
```bash
# Via pip
pip3 install yamllint

# Ubuntu/Debian
sudo apt-get install yamllint

# Arch Linux
sudo pacman -S yamllint
```

### For Advanced Features

#### Socat (QMP/Monitor Socket Control)

**Installation:**
```bash
# Ubuntu/Debian
sudo apt-get install socat

# Arch Linux
sudo pacman -S socat

# macOS
brew install socat
```

#### Screen or Tmux (Serial Console)

**Installation:**
```bash
# Ubuntu/Debian
sudo apt-get install screen

# Arch Linux
sudo pacman -S screen

# macOS
brew install screen
```

#### Telnet Client (Serial Console Alternative)

**Installation:**
```bash
# Ubuntu/Debian
sudo apt-get install telnet

# Arch Linux
sudo pacman -S inetutils

# macOS (pre-installed)
# No installation needed
```

---

## Build Dependencies

### For Building from Source

#### Make

**Installation:**
```bash
# Ubuntu/Debian
sudo apt-get install build-essential

# Arch Linux
sudo pacman -S base-devel

# macOS
xcode-select --install
```

#### QEMU Tools (for manual image manipulation)

**Installation:**
```bash
# Ubuntu/Debian
sudo apt-get install qemu-utils

# Arch Linux
sudo pacman -S qemu-img

# macOS
brew install qemu
```

**Tools Included:**
- `qemu-img` - Disk image creation and conversion
- `qemu-nbd` - Network block device support

### For AUR Package (Arch Linux Only)

**Required Packages:**
```bash
sudo pacman -S base-devel
```

**Building PKGBUILD:**
```bash
# Clone repository
git clone https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker.git
cd gnu-hurd-docker

# Build package
makepkg -si

# Or install from AUR (when published)
yay -S gnu-hurd-docker
```

---

## Runtime Dependencies

### Inside Docker Container

The Docker image includes all required QEMU components:

**Packages (Debian Bookworm base):**
- `qemu-system-i386` - i386 system emulator
- `qemu-utils` - QEMU utilities (qemu-img, etc.)
- `screen` - Terminal multiplexer
- `telnet` - Telnet client
- `curl` - HTTP client
- `socat` - Socket relay

**QEMU Version:** 7.2 or later (from Debian Bookworm)

### Guest OS (GNU/Hurd)

**Image Requirements:**
- Debian GNU/Hurd i386 image
- Format: QCOW2
- Size: ~2-4 GB compressed, ~10 GB expanded
- Download: Provided by `scripts/download-image.sh`

**Image Source:**
```bash
# Automated download script (recommended)
./scripts/download-image.sh

# Manual download (Debian 13 "Trixie" x86_64 - 2025-11-05 release)
wget https://cdimage.debian.org/cdimage/ports/13.0/hurd-amd64/debian-hurd.img.tar.xz
tar xJf debian-hurd.img.tar.xz
qemu-img convert -f raw -O qcow2 debian-hurd.img debian-hurd-amd64.qcow2
```

---

## Network Requirements

### Firewall Rules

**Docker requires:**
- Outbound internet access for pulling images
- iptables/nftables NAT support

**Guest access requires:**
- Port 2222 (SSH) - forwarded to guest:22
- Port 8080 (HTTP) - forwarded to guest:80
- Port 5555 (Serial) - telnet console
- Port 9999 (Custom) - application-specific

**Firewall Configuration (Linux):**
```bash
# Allow Docker bridge network
sudo iptables -A INPUT -i docker0 -j ACCEPT

# Allow forwarded ports (if host firewall enabled)
sudo iptables -A INPUT -p tcp --dport 2222 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 5555 -j ACCEPT
```

### DNS Requirements

**Required for:**
- Docker image pulls (registry.hub.docker.com, ghcr.io)
- Guest OS package updates (deb.debian.org)
- Script downloads (github.com, debian.org)

**Configuration:**
```bash
# Verify DNS works
dig github.com
nslookup github.com

# Test Docker registry access
docker pull hello-world
```

---

## Storage Requirements

### Disk Space Breakdown

| Component | Size | Purpose |
|-----------|------|---------|
| Docker images | 500 MB | Base Debian + QEMU packages |
| QCOW2 image | 2-4 GB | Debian GNU/Hurd guest OS |
| Build cache | 1-2 GB | Docker layer cache |
| Snapshots (optional) | Variable | QEMU snapshots |
| Logs | 100-500 MB | QEMU and container logs |
| **Total** | **5-10 GB** | Minimum required |

**Recommended:** 20 GB free for comfortable development

### Filesystem Requirements

**Supported:**
- ext4, xfs, btrfs (Linux)
- APFS (macOS)
- NTFS (Windows/WSL 2)

**Not Recommended:**
- NFS, CIFS (network filesystems) - poor performance
- FAT32 - no Unix permissions support

### I/O Performance

**SSD Recommended:**
- Random I/O: 10,000+ IOPS
- Sequential read: 500+ MB/s
- Sequential write: 300+ MB/s

**HDD (acceptable but slower):**
- 7200 RPM minimum
- Expect 2-3x slower boot times

---

## Platform-Specific Notes

### Linux with KVM

**Best Performance Configuration:**
```yaml
# docker-compose.yml
devices:
  - /dev/kvm

environment:
  - QEMU_RAM=4096
  - QEMU_SMP=2
```

**Expected Performance:**
- Boot time: 30-60 seconds
- CPU performance: ~80-90% of native
- I/O performance: Limited by QEMU caching

### macOS (TCG Mode)

**Performance Expectations:**
```yaml
# No KVM device
environment:
  - QEMU_RAM=2048
  - QEMU_SMP=1
```

**Expected Performance:**
- Boot time: 2-3 minutes
- CPU performance: ~10-20% of native (TCG emulation)
- I/O performance: Adequate for development

### Windows/WSL 2

**Configuration:**
```yaml
# WSL 2 backend
environment:
  - QEMU_RAM=2048
  - QEMU_SMP=1
  - DISPLAY_MODE=vnc
```

**Expected Performance:**
- Boot time: 2-4 minutes
- Performance varies with WSL 2 configuration
- Consider WSL 2 memory limit adjustments

---

## Verification Checklist

Use this checklist to verify all requirements are met:

```bash
# 1. Docker Engine
docker --version
docker ps

# 2. Docker Compose
docker-compose --version

# 3. Git
git --version

# 4. Disk Space
df -h .

# 5. KVM (Linux only)
ls -l /dev/kvm
lsmod | grep kvm

# 6. Network
docker pull hello-world

# 7. Permissions
groups | grep docker

# 8. Memory
free -h

# 9. CPU
nproc
lscpu | grep -i virtual

# 10. QEMU (inside container)
docker run --rm debian:bookworm-slim apt-cache policy qemu-system-i386
```

---

## Troubleshooting Requirements

### Docker Installation Issues

**Error: Cannot connect to Docker daemon**
```bash
# Check if Docker is running
sudo systemctl status docker

# Start Docker
sudo systemctl start docker

# Add user to docker group
sudo usermod -aG docker $USER
newgrp docker
```

**Error: permission denied while trying to connect to Docker**
```bash
# Verify group membership
groups | grep docker

# If not in docker group
sudo usermod -aG docker $USER
# Log out and log back in
```

### KVM Issues (Linux)

**Error: Could not access KVM kernel module**
```bash
# Load KVM module
sudo modprobe kvm
sudo modprobe kvm_intel  # or kvm_amd

# Add to auto-load
echo "kvm" | sudo tee -a /etc/modules-load.d/kvm.conf
echo "kvm_intel" | sudo tee -a /etc/modules-load.d/kvm.conf

# Fix permissions
sudo chmod 666 /dev/kvm
# Or add user to kvm group
sudo usermod -aG kvm $USER
```

### Network Issues

**Error: iptables CHAIN_ADD failed**
```bash
# Load nf_tables modules
sudo modprobe nf_tables
sudo modprobe nf_tables_ipv4
sudo modprobe nft_masq
sudo modprobe nf_nat

# Make permanent
cat <<EOF | sudo tee /etc/modules-load.d/docker.conf
nf_tables
nf_tables_ipv4
nft_masq
nf_nat
EOF
```

**Error: Cannot pull Docker images**
```bash
# Check DNS
nslookup registry.hub.docker.com

# Configure Docker DNS
sudo mkdir -p /etc/docker
cat <<EOF | sudo tee /etc/docker/daemon.json
{
  "dns": ["8.8.8.8", "8.8.4.4"]
}
EOF
sudo systemctl restart docker
```

---

## References

- [Docker Installation](https://docs.docker.com/engine/install/)
- [Docker Compose Installation](https://docs.docker.com/compose/install/)
- [KVM Setup](https://www.linux-kvm.org/page/Downloads)
- [GNU/Hurd](https://www.gnu.org/software/hurd/)
- [Debian GNU/Hurd](https://www.debian.org/ports/hurd/)
- [QEMU Documentation](https://www.qemu.org/documentation/)

---

**Status:** Complete and Validated  
**Maintainer:** Oichkatzelesfrettschen  
**Last Audit:** 2025-11-06
