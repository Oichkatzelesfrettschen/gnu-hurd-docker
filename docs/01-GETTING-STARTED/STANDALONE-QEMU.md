# GNU/Hurd Docker - Standalone QEMU Guide

**Last Updated**: 2025-11-08
**Purpose**: Complete guide for running GNU/Hurd directly with QEMU without Docker
**Architecture**: x86_64 only

---

## Overview

WHY: Some users need direct QEMU control without container overhead.
WHAT: Run GNU/Hurd using QEMU directly on your host system.
HOW: Use the `scripts/run-hurd-qemu.sh` script with appropriate configuration.

This guide covers running Debian GNU/Hurd using QEMU directly on your Linux host, bypassing Docker entirely. This mode offers maximum performance and flexibility at the cost of additional setup complexity.

---

## Prerequisites

### System Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| **CPU** | x86_64, 2 cores | x86_64, 4+ cores with VT-x/AMD-V |
| **RAM** | 4 GB system total | 8 GB system total |
| **Disk** | 10 GB free space | 20 GB free SSD space |
| **OS** | Linux kernel 4.x+ | Linux kernel 5.x+ with KVM |

### Software Installation

#### Arch Linux
```bash
# Full QEMU with all architectures and tools
sudo pacman -S qemu-full

# Or minimal for x86_64 only
sudo pacman -S qemu-system-x86 qemu-img
```

#### Debian/Ubuntu
```bash
# QEMU with KVM support
sudo apt-get update
sudo apt-get install qemu-system-x86 qemu-utils

# Optional: KVM acceleration
sudo apt-get install qemu-kvm
```

#### Fedora/RHEL
```bash
# QEMU with standard tools
sudo dnf install qemu-system-x86 qemu-img

# Optional: KVM group for acceleration
sudo dnf install @virtualization
```

### KVM Setup (Recommended)

WHY: KVM provides near-native performance through hardware virtualization.
WHAT: Kernel-based Virtual Machine acceleration for QEMU.
HOW: Verify and configure KVM access.

1. **Check CPU virtualization support**:
```bash
# Intel processors
grep -E 'vmx' /proc/cpuinfo

# AMD processors
grep -E 'svm' /proc/cpuinfo

# If output is empty, KVM is not supported
```

2. **Verify KVM kernel module**:
```bash
# Check if loaded
lsmod | grep kvm

# Load manually if needed
sudo modprobe kvm
sudo modprobe kvm_intel  # For Intel
# OR
sudo modprobe kvm_amd    # For AMD
```

3. **Check KVM device permissions**:
```bash
# Should exist and be accessible
ls -l /dev/kvm

# Add user to kvm group (logout required)
sudo usermod -aG kvm $USER
```

---

## Download and Setup

### Step 1: Clone Repository
```bash
# Clone the project
git clone https://github.com/your-repo/gnu-hurd-docker.git
cd gnu-hurd-docker
```

### Step 2: Download Hurd Image

Use the provided setup script:
```bash
# Download x86_64 image (337 MB download, expands to 80 GB sparse)
./scripts/setup-hurd-amd64.sh

# Image will be saved to: images/debian-hurd-amd64.qcow2
```

Or download manually:
```bash
# Create images directory
mkdir -p images

# Download from mirror
wget -O images/debian-hurd-amd64-20250807.img.tar.xz \
  https://darnassus.sceen.net/~hurd-web/debian-amd64-debian-installer/2025-08-07/debian-hurd-amd64-20250807.img.tar.xz

# Extract (creates .img file)
cd images
tar xf debian-hurd-amd64-20250807.img.tar.xz

# Convert to QCOW2 for better performance
qemu-img convert -O qcow2 debian-hurd-amd64-20250807.img debian-hurd-amd64.qcow2

# Optional: Remove original files to save space
rm debian-hurd-amd64-20250807.img debian-hurd-amd64-20250807.img.tar.xz
```

---

## Basic Usage

### Quick Start
```bash
# Run with defaults (auto-detects image, uses KVM if available)
./scripts/run-hurd-qemu.sh

# System will boot, showing QEMU monitor
# Wait 2-5 minutes for full boot
# Then SSH from another terminal:
ssh -p 2222 root@localhost
# Password: root
```

### Command Line Options

```bash
# Show all options
./scripts/run-hurd-qemu.sh --help

# Common usage patterns:

# Custom memory and CPU
./scripts/run-hurd-qemu.sh --memory 8192 --cpus 4

# Specific image path
./scripts/run-hurd-qemu.sh --image /path/to/debian-hurd.qcow2

# Different SSH port (avoid conflicts)
./scripts/run-hurd-qemu.sh --ssh-port 2223

# Force TCG emulation (no KVM)
./scripts/run-hurd-qemu.sh --no-kvm

# Enable VNC display
./scripts/run-hurd-qemu.sh --vnc :0
# Connect with: vncviewer localhost:5900
```

### Environment Variables

Configure via environment instead of CLI arguments:

```bash
# Set defaults
export QEMU_IMAGE="/path/to/custom-hurd.qcow2"
export QEMU_RAM=8192
export QEMU_SMP=4
export SSH_PORT=2223
export SERIAL_PORT=5556

# Run with environment config
./scripts/run-hurd-qemu.sh

# Override specific setting
QEMU_RAM=16384 ./scripts/run-hurd-qemu.sh

# Force TCG mode
DISABLE_KVM=1 ./scripts/run-hurd-qemu.sh
```

---

## Advanced Configuration

### Performance Tuning

**CPU Configuration**:
```bash
# Maximum performance with KVM
./scripts/run-hurd-qemu.sh --cpus 4

# Note: Hurd is stable with 1-2 cores, experimental with 4+
```

**Memory Configuration**:
```bash
# Development workload
./scripts/run-hurd-qemu.sh --memory 4096

# Compilation/building
./scripts/run-hurd-qemu.sh --memory 8192

# Minimum for basic operation
./scripts/run-hurd-qemu.sh --memory 2048
```

### Network Configuration

Default configuration provides:
- **SSH**: Port 2222 -> VM port 22
- **HTTP**: Port 8080 -> VM port 80 (if needed)
- **Custom**: Add more forwards by editing the script

Custom port forwarding (edit script):
```bash
# In run-hurd-qemu.sh, find NETWORK_OPTS
NETWORK_OPTS="-netdev user,id=net0,hostfwd=tcp::2222-:22,hostfwd=tcp::8080-:80,hostfwd=tcp::3000-:3000"
```

### Display Options

**Serial Console** (default):
```bash
# Connects automatically, or use telnet
telnet localhost 5555
```

**VNC Display**:
```bash
# Start with VNC
./scripts/run-hurd-qemu.sh --vnc :1

# Connect from client
vncviewer localhost:5901
```

**SDL Display** (modify script):
```bash
# Replace -nographic with
-display sdl
```

**SPICE Display** (modify script):
```bash
# Advanced remote display
-spice port=5930,disable-ticketing -display spice-app
```

### Storage Management

**Using Snapshots**:
```bash
# Create snapshot before risky operations
qemu-img snapshot -c before-update images/debian-hurd-amd64.qcow2

# List snapshots
qemu-img snapshot -l images/debian-hurd-amd64.qcow2

# Restore snapshot
qemu-img snapshot -a before-update images/debian-hurd-amd64.qcow2
```

**Additional Disks** (modify script):
```bash
# Add second disk for data
-drive file=data.qcow2,if=virtio,index=1
```

---

## Common Workflows

### Development Workflow

```bash
# 1. Start VM with extra resources
./scripts/run-hurd-qemu.sh --memory 8192 --cpus 4

# 2. SSH for development
ssh -p 2222 agents@localhost

# 3. Transfer files
scp -P 2222 myfile.c root@localhost:/root/

# 4. Compile in VM
ssh -p 2222 root@localhost "gcc -o myprogram myfile.c"

# 5. Shutdown cleanly
ssh -p 2222 root@localhost "shutdown -h now"
```

### Testing Workflow

```bash
# 1. Create clean snapshot
qemu-img snapshot -c clean-state images/debian-hurd-amd64.qcow2

# 2. Run tests
./scripts/run-hurd-qemu.sh
ssh -p 2222 root@localhost "run-tests.sh"

# 3. Restore clean state for next test
qemu-img snapshot -a clean-state images/debian-hurd-amd64.qcow2
```

### Debugging Workflow

```bash
# 1. Run with GDB server
./scripts/run-hurd-qemu.sh  # Then in QEMU monitor: (qemu) gdbserver

# 2. Connect GDB
gdb
(gdb) target remote localhost:1234
(gdb) continue
```

---

## Troubleshooting

### KVM Issues

**Problem**: "Could not access KVM kernel module"
```bash
# Solution 1: Load KVM module
sudo modprobe kvm
sudo modprobe kvm_intel  # or kvm_amd

# Solution 2: Fix permissions
sudo chmod 666 /dev/kvm
# OR add user to kvm group
sudo usermod -aG kvm $USER
# Logout and login again

# Solution 3: Disable KVM (use TCG)
./scripts/run-hurd-qemu.sh --no-kvm
```

**Problem**: "KVM acceleration not available"
```bash
# Check virtualization enabled in BIOS
dmesg | grep -i virtual

# Verify CPU supports virtualization
egrep -c '(vmx|svm)' /proc/cpuinfo
# Should return > 0
```

### Port Conflicts

**Problem**: "Failed to bind socket: Address already in use"
```bash
# Check what's using the port
sudo lsof -i :2222
sudo netstat -tlnp | grep 2222

# Solution: Use different port
./scripts/run-hurd-qemu.sh --ssh-port 2223
ssh -p 2223 root@localhost
```

### Image Not Found

**Problem**: "QCOW2 image not found"
```bash
# Check image location
ls -la images/

# Specify path explicitly
./scripts/run-hurd-qemu.sh --image /full/path/to/debian-hurd-amd64.qcow2

# Or set environment
export QEMU_IMAGE="/full/path/to/debian-hurd-amd64.qcow2"
./scripts/run-hurd-qemu.sh
```

### Performance Issues

**Problem**: "VM runs very slowly"
```bash
# Verify KVM is active
./scripts/run-hurd-qemu.sh 2>&1 | grep -i kvm
# Should show: "KVM acceleration enabled"

# If not, check KVM setup (see above)

# Increase memory
./scripts/run-hurd-qemu.sh --memory 8192

# Check host resources
top  # Verify CPU and memory available
```

### SSH Connection Refused

**Problem**: "Connection refused on port 2222"
```bash
# Wait for full boot (2-5 minutes)
# Check serial console for boot progress
telnet localhost 5555

# Verify QEMU is running
ps aux | grep qemu

# Check port forwarding
netstat -tlnp | grep 2222
```

---

## Script Internals

The `run-hurd-qemu.sh` script handles:

1. **KVM Detection**: Automatically checks for KVM and falls back to TCG
2. **Image Discovery**: Searches current dir and images/ for QCOW2 files
3. **Network Setup**: Configures user-mode networking with port forwarding
4. **Signal Handling**: Proper cleanup on Ctrl-C
5. **Logging**: Colored output for status messages

Key configuration in script:
```bash
# Core QEMU command structure
qemu-system-x86_64 \
  -machine pc \
  -cpu max \
  -m 4096 \
  -smp 2 \
  -drive file=IMAGE,if=virtio,cache=writeback \
  -netdev user,id=net0,hostfwd=tcp::2222-:22 \
  -device e1000,netdev=net0 \
  -serial telnet:localhost:5555,server,nowait \
  -nographic
```

---

## Comparison with Docker Mode

| Aspect | Standalone QEMU | Docker Mode |
|--------|-----------------|-------------|
| **Setup** | Manual QEMU install | Just Docker |
| **Performance** | Best (direct KVM) | Good (5-10% overhead) |
| **Management** | Manual process control | docker compose commands |
| **Logs** | QEMU output only | Docker + QEMU logs |
| **Cleanup** | Kill process | docker compose down |
| **Updates** | Manual QEMU updates | Container updates |

---

## Security Considerations

Running QEMU directly:

1. **Process Isolation**: QEMU runs as your user, no container isolation
2. **Network**: User-mode networking is relatively safe
3. **KVM Access**: Requires kvm group membership or root
4. **Resource Limits**: No automatic limits, can consume all host resources

Best practices:
- Run as non-root user when possible
- Use user-mode networking unless bridging required
- Set resource limits via systemd or cgroups if needed
- Keep QEMU updated for security patches

---

## Next Steps

- Review [USAGE-MODES.md](USAGE-MODES.md) to confirm this is the right mode
- See [../04-OPERATION/INTERACTIVE-ACCESS.md](../04-OPERATION/INTERACTIVE-ACCESS.md) for SSH and console usage
- Check [../06-TROUBLESHOOTING/COMMON-ISSUES.md](../06-TROUBLESHOOTING/COMMON-ISSUES.md) for more solutions
- Read script source: `scripts/run-hurd-qemu.sh` for customization

---

## Summary

Standalone QEMU mode provides:
- Maximum performance through direct KVM access
- Full control over QEMU configuration
- Minimal overhead and dependencies
- Direct integration with host tools

Use this mode when Docker overhead is unacceptable or when you need specific QEMU features not exposed through the container interface.