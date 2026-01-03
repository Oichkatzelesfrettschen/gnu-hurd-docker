# Platform-Specific Setup Guide

## Overview

This guide provides detailed setup instructions for GNU/Hurd Docker across different operating systems and architectures. The project supports Docker and Podman on Linux, macOS, Windows, and BSD systems.

## Quick Platform Guide

| Platform | Container Runtime | KVM/Acceleration | Boot Time | Setup Difficulty |
|----------|-------------------|------------------|-----------|------------------|
| Linux (x86_64) | Docker/Podman | KVM | 30-60s | ⭐ Easy |
| Linux (ARM64) | Docker/Podman | TCG only | 3-5min | ⭐⭐ Moderate |
| macOS (Intel) | Docker/Podman | HVF | 1-2min | ⭐⭐ Moderate |
| macOS (Apple Silicon) | Docker/Podman | TCG only | 3-5min | ⭐⭐ Moderate |
| Windows (WSL2) | Docker/Podman | KVM via WSL | 30-60s | ⭐⭐⭐ Complex |
| FreeBSD | Podman | TCG only | 3-5min | ⭐⭐⭐ Complex |

## Linux Setup

### Prerequisites

- Linux kernel 4.4+ (5.x+ recommended)
- 8GB RAM minimum (16GB recommended)
- 20GB free disk space
- CPU: x86_64 or ARM64

### Option 1: Docker Installation

#### Ubuntu/Debian

```bash
# Remove old versions
sudo apt-get remove docker docker-engine docker.io containerd runc

# Update and install dependencies
sudo apt-get update
sudo apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

# Add Docker GPG key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Add Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Add user to docker group
sudo usermod -aG docker $USER

# Reboot or re-login
newgrp docker
```

#### Fedora/RHEL/CentOS

```bash
# Install Docker
sudo dnf install -y docker docker-compose
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
newgrp docker
```

#### Arch Linux

```bash
sudo pacman -S docker docker-compose
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
newgrp docker
```

### Option 2: Podman Installation

#### Ubuntu/Debian

```bash
# Ubuntu 20.10+
sudo apt-get update
sudo apt-get install -y podman podman-compose

# Ubuntu 20.04 and earlier
. /etc/os-release
echo "deb https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/xUbuntu_${VERSION_ID}/ /" | \
  sudo tee /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list
curl -L "https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/xUbuntu_${VERSION_ID}/Release.key" | \
  sudo apt-key add -
sudo apt-get update
sudo apt-get install -y podman

# Install podman-compose
pip3 install --user podman-compose
```

#### Fedora/RHEL

```bash
sudo dnf install -y podman podman-compose
```

### Enable KVM (Linux Only)

```bash
# Check if KVM is available
lsmod | grep kvm

# If not loaded, load kernel module
sudo modprobe kvm
sudo modprobe kvm_intel  # For Intel CPUs
# OR
sudo modprobe kvm_amd    # For AMD CPUs

# Add user to kvm group
sudo usermod -aG kvm $USER

# Set permissions
sudo chmod 666 /dev/kvm

# Make permanent (add to udev rules)
echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666"' | sudo tee /etc/udev/rules.d/99-kvm.rules
sudo udevadm control --reload-rules
sudo udevadm trigger --name-match=kvm

# Verify
ls -l /dev/kvm
```

### Project Setup (Linux)

```bash
# Clone repository
git clone https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker.git
cd gnu-hurd-docker

# Install development dependencies
make install-deps

# Check platform
make platform-check

# Build and start
make build
make up

# Monitor boot (wait 30-60s with KVM)
make logs

# Connect via SSH
ssh -p 2222 root@localhost
```

## macOS Setup

### Prerequisites

- macOS 11 (Big Sur) or later
- 8GB RAM minimum (16GB recommended)
- 20GB free disk space
- Intel or Apple Silicon

### Option 1: Docker Desktop

#### Installation

```bash
# Download Docker Desktop
# Intel: https://desktop.docker.com/mac/main/amd64/Docker.dmg
# Apple Silicon: https://desktop.docker.com/mac/main/arm64/Docker.dmg

# Or via Homebrew
brew install --cask docker

# Start Docker Desktop from Applications
# Wait for Docker to start
```

#### Configuration

```bash
# Increase resources in Docker Desktop
# Settings → Resources:
# - CPUs: 4+
# - Memory: 8GB+
# - Disk: 20GB+
```

### Option 2: Podman

#### Installation

```bash
# Install Podman
brew install podman

# Install podman-compose
pip3 install podman-compose

# Initialize Podman machine
podman machine init --cpus 4 --memory 8192 --disk-size 50

# Start Podman machine
podman machine start

# Set up alias (optional)
echo 'alias docker=podman' >> ~/.zshrc
source ~/.zshrc
```

### Project Setup (macOS)

```bash
# Clone repository
git clone https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker.git
cd gnu-hurd-docker

# Install development dependencies
brew install shellcheck yamllint hadolint
pip3 install black flake8 pylint mkdocs-material

# Check platform
make platform-check

# Note: No KVM on macOS - expect slower boot (3-5min)

# Build and start
make build
make up

# Monitor boot
make logs

# Connect via SSH (after boot completes)
ssh -p 2222 root@localhost
```

### Apple Silicon Notes

- Container runs on ARM64 (native)
- QEMU emulates x86_64 for Hurd guest (TCG mode)
- Boot time: 3-5 minutes (no hardware acceleration)
- Full functionality maintained

## Windows Setup

### Prerequisites

- Windows 10/11 Pro, Enterprise, or Education (for Hyper-V)
- WSL 2 enabled
- 8GB RAM minimum (16GB recommended)
- 20GB free disk space

### Option 1: Docker Desktop + WSL2

#### Enable WSL2

```powershell
# In PowerShell (Administrator)
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart

# Restart computer

# Set WSL 2 as default
wsl --set-default-version 2

# Install Ubuntu from Microsoft Store
# Or download: https://aka.ms/wslubuntu2004
```

#### Install Docker Desktop

```powershell
# Download from: https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe

# Or via winget
winget install Docker.DockerDesktop

# Enable WSL 2 integration in Docker Desktop settings
```

#### Setup in WSL2

```bash
# Open Ubuntu in WSL2
wsl -d Ubuntu

# Update system
sudo apt-get update
sudo apt-get upgrade -y

# Clone repository
git clone https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker.git
cd gnu-hurd-docker

# Install dependencies
make install-deps

# Check platform
make platform-check

# Build and start
make build
make up
```

### Option 2: Podman in WSL2

```bash
# In WSL2 Ubuntu
sudo apt-get update
sudo apt-get install -y podman podman-compose

# Configure podman
podman system info

# Clone and setup
git clone https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker.git
cd gnu-hurd-docker

make CONTAINER_RUNTIME=podman platform-check
make CONTAINER_RUNTIME=podman up
```

### Windows Performance Tips

1. **Allocate Resources to WSL2**

Create/edit `.wslconfig` in `%USERPROFILE%`:

```ini
[wsl2]
memory=8GB
processors=4
swap=2GB
```

2. **Use Native Linux Filesystem**

Store project in WSL2 filesystem (`~/` not `/mnt/c/`):

```bash
# Good: ~/projects/gnu-hurd-docker
# Bad:  /mnt/c/Users/YourName/projects/gnu-hurd-docker
```

3. **Enable KVM in WSL2**

Recent Windows 11 builds support nested virtualization:

```bash
# Check if KVM available
ls -l /dev/kvm

# If not, update WSL2 kernel
wsl --update
```

## BSD Setup

### FreeBSD

#### Install Podman

```bash
# Install podman
pkg install podman

# Install Python and podman-compose
pkg install python39 py39-pip
pip install podman-compose

# Enable and start podman
sysrc podman_enable="YES"
service podman start
```

#### Project Setup

```bash
# Clone repository
git clone https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker.git
cd gnu-hurd-docker

# Install dependencies
pkg install shellcheck yamllint

# Setup
make CONTAINER_RUNTIME=podman platform-check
make CONTAINER_RUNTIME=podman build
make CONTAINER_RUNTIME=podman up
```

### OpenBSD/NetBSD

**Note**: Docker/Podman support is limited on OpenBSD/NetBSD. Consider:

1. **Native VM**: Use bhyve or native hypervisor
2. **Linux VM**: Run Linux VM with Docker/Podman inside
3. **Cloud**: Use cloud-based containers

## Platform Comparison

### Boot Time Comparison

| Platform | Runtime | Acceleration | Boot Time | Notes |
|----------|---------|--------------|-----------|-------|
| Linux x86_64 | Docker | KVM | 30-60s | Optimal |
| Linux x86_64 | Podman | KVM | 30-60s | Optimal |
| Linux ARM64 | Docker | TCG | 3-5min | Emulation overhead |
| Linux ARM64 | Podman | TCG | 3-5min | Emulation overhead |
| macOS Intel | Docker | HVF | 1-2min | Good |
| macOS Intel | Podman | HVF | 1-2min | Good |
| macOS M1/M2/M3 | Docker | TCG | 3-5min | Cross-architecture |
| macOS M1/M2/M3 | Podman | TCG | 3-5min | Cross-architecture |
| Windows WSL2 | Docker | KVM | 30-60s | Good (recent builds) |
| Windows WSL2 | Podman | KVM | 30-60s | Good (recent builds) |
| FreeBSD | Podman | TCG | 3-5min | Experimental |

### Resource Requirements

| Platform | Minimum RAM | Recommended RAM | CPU Cores |
|----------|-------------|-----------------|-----------|
| Linux KVM | 6GB | 16GB | 2+ |
| Linux TCG | 6GB | 16GB | 4+ |
| macOS | 8GB | 16GB | 4+ |
| Windows WSL2 | 8GB | 16GB | 4+ |
| BSD | 6GB | 16GB | 4+ |

## Troubleshooting

### Common Issues

#### "No container runtime found"

```bash
# Install Docker or Podman
make install-runtime

# Or manually follow installation instructions above
```

#### "Permission denied: /dev/kvm"

```bash
# Linux only
sudo usermod -aG kvm $USER
sudo chmod 666 /dev/kvm
newgrp kvm
```

#### "Slow boot times"

Check acceleration:
```bash
make platform-check

# If KVM: no -> follow KVM setup instructions
# If macOS/Windows: expected (no native acceleration)
```

#### "Container won't start"

```bash
# Check logs
make logs

# Verify runtime
make platform-check

# Clean and restart
make clean-all
make build
make up
```

### Platform-Specific Issues

#### macOS: "Cannot connect to Docker daemon"

```bash
# Ensure Docker Desktop is running
open /Applications/Docker.app

# Or restart Docker
killall Docker && open /Applications/Docker.app
```

#### Windows: "WSL 2 installation is incomplete"

```powershell
# Update WSL
wsl --update

# Check version
wsl --list --verbose

# Should show version 2
```

#### Linux: "KVM not working"

```bash
# Check CPU virtualization support
egrep -c '(vmx|svm)' /proc/cpuinfo
# Should be > 0

# Check kernel module
lsmod | grep kvm

# Enable in BIOS if needed
# Intel: Enable VT-x
# AMD: Enable AMD-V
```

## Best Practices

### All Platforms

1. **Use Makefile**: Abstracts platform differences
   ```bash
   make help  # See all commands
   ```

2. **Check Platform**: Before starting
   ```bash
   make platform-check
   ```

3. **Monitor Boot**: First time setup
   ```bash
   make logs
   ```

4. **Allocate Resources**: Sufficient RAM and CPU
   - Minimum: 6-8GB RAM, 2 CPUs
   - Recommended: 16GB RAM, 4+ CPUs

5. **Use SSD**: Better I/O performance

### Development

1. **Use Native Filesystem**: Best performance
   - Linux: ~/projects
   - macOS: ~/projects
   - Windows: ~ (not /mnt/c)

2. **Enable KVM**: When available (Linux, WSL2)

3. **Create Snapshots**: Before major changes
   ```bash
   make snapshot NAME=pre-experiment
   ```

## Summary

✅ **Linux**: Best support, KVM acceleration, optimal performance  
✅ **macOS**: Full support, good Intel performance, slower on Apple Silicon  
✅ **Windows**: Full support via WSL2, good performance with recent builds  
⚠️ **BSD**: Experimental, use Podman, slower performance  

**Quick Start Any Platform**:
```bash
git clone https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker.git
cd gnu-hurd-docker
make platform-check
make build
make up
make logs
```

**Need Help?** See `docs/06-TROUBLESHOOTING/` for detailed troubleshooting guides.
