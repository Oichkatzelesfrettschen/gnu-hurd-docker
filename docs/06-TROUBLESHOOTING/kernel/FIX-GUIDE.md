# GNU/Hurd Docker - Kernel Networking Fix Guide

## Problem

Docker daemon fails to start with error:

```
CHAIN_ADD failed (No such file or directory): chain PREROUTING
iptables v1.8.11 (nf_tables): CHAIN_ADD failed
```

## Root Cause

Linux kernel nf_tables subsystem is not properly initialized with required NAT table chains (PREROUTING, POSTROUTING, INPUT, OUTPUT).

This is a **system-level kernel configuration issue**, not a Docker or Docker Compose problem.

## Prerequisites Check

Before attempting fixes, check your current configuration:

```bash
# Check kernel version
uname -r

# Check if nf_tables module exists
modinfo nf_tables

# Check if nf_tables is loaded
lsmod | grep nf_tables

# Check iptables mode
ls -la /usr/bin/iptables | grep -o "iptables[^']*"

# Try to start Docker
systemctl status docker
```

## Three Solutions (Select One)

### Option 1: Rebuild Kernel with nf_tables Support (RECOMMENDED - Long-term)

**Pros:**
- Permanent fix at kernel level
- Best long-term solution
- Required for production systems

**Cons:**
- Requires 2-3 hours compile time
- Needs 10+ GB free disk space
- Requires linux-headers and gcc

**Steps:**

```bash
# Install build dependencies
sudo pacman -S base-devel linux-headers

# Clone CachyOS kernel sources
git clone https://github.com/CachyOS/linux-cachyos
cd linux-cachyos

# Copy current kernel config as base
cp /proc/config.gz ./
gunzip config.gz
mv config .config

# Edit kernel config to enable nf_tables
# Required options:
# CONFIG_NETFILTER=y
# CONFIG_NETFILTER_XTABLES=y
# CONFIG_NF_NAT=y
# CONFIG_NETFILTER_XT_TARGET_MASQUERADE=y
# CONFIG_NF_TABLES=y
# CONFIG_NF_TABLES_IPV4=y
# CONFIG_NF_TABLES_NAT=y
# CONFIG_NF_NAT_IPV4=y

# Use interactive menu editor
make menuconfig
# Navigate to: Networking > Netfilter Configuration
# Enable all required options above

# Build and install (replace 4 with your CPU core count)
time makepkg -fsi --jobs=4

# Reboot to activate new kernel
sudo reboot
```

After reboot, verify Docker works:
```bash
docker ps
```

### Option 2: Load nf_tables Kernel Modules (QUICK FIX)

**Pros:**
- Fast (seconds to apply)
- No reboot needed
- Minimal resource usage

**Cons:**
- Only works if modules are compiled in kernel
- Lost after reboot (unless made permanent)
- May not work on all kernel configurations

**Steps:**

```bash
# Check if modules are available
modinfo nf_tables

# Load required modules
sudo modprobe nf_tables
sudo modprobe nf_tables_ipv4
sudo modprobe nft_masq
sudo modprobe nf_nat

# Verify modules loaded
lsmod | grep -E "nf_tables|nf_nat"

# Restart Docker daemon
sudo systemctl restart docker

# Test Docker
docker ps
```

**Make Permanent (survives reboot):**

```bash
# Add to /etc/modules-load.d/
echo "nf_tables" | sudo tee /etc/modules-load.d/docker.conf
echo "nf_tables_ipv4" | sudo tee -a /etc/modules-load.d/docker.conf
echo "nft_masq" | sudo tee -a /etc/modules-load.d/docker.conf
echo "nf_nat" | sudo tee -a /etc/modules-load.d/docker.conf

# Reboot to verify
sudo reboot
```

### Option 3: Switch to iptables-legacy (TEMPORARY WORKAROUND)

**Pros:**
- Fast to implement
- No recompilation needed
- Works immediately

**Cons:**
- Temporary workaround, not permanent fix
- Legacy mode has reduced functionality
- May have compatibility issues with newer tools

**Steps:**

```bash
# Install iptables-legacy package
sudo pacman -S iptables-legacy

# Switch to legacy mode
sudo update-alternatives --set iptables /usr/bin/iptables-legacy
sudo update-alternatives --set ip6tables /usr/bin/ip6tables-legacy

# Verify switch
ls -la /usr/bin/iptables | grep iptables

# Restart Docker daemon
sudo systemctl restart docker

# Test Docker
docker ps
```

**Revert to nftables mode:**

```bash
# Switch back if needed
sudo update-alternatives --set iptables /usr/bin/iptables-nft
sudo update-alternatives --set ip6tables /usr/bin/ip6tables-nft
sudo systemctl restart docker
```

## Automated Fix Package

An Arch Linux PKGBUILD is provided: `gnu-hurd-docker-kernel-fix`

```bash
# Install package
cd /home/eirikr/Playground/gnu-hurd-docker
makepkg -fsi

# Run automated fix script
sudo gnu-hurd-docker-kernel-fix
```

The package provides:
- Automated detection of current networking status
- Diagnostic tool to check kernel capabilities
- Installation of recommended packages
- Post-install hooks to apply fixes

## Verification

After applying any fix, verify Docker is functional:

```bash
# Check Docker daemon status
systemctl status docker

# List containers
docker ps

# Verify Docker Compose works
docker-compose --version
docker-compose ps

# Build test image (minimal)
docker build --tag test:latest - << 'EOF'
FROM debian:bookworm
RUN echo "Docker works!"
EOF

# Run test container
docker run --rm test:latest
```

## Troubleshooting

### Docker still fails after Option 2

**Symptom:** `modprobe nf_tables` works, but Docker still won't start

**Solution:** Check kernel config has nf_tables support:
```bash
zgrep CONFIG_NF_TABLES /proc/config.gz
# Should show: CONFIG_NF_TABLES=m (or =y)
# If shows "is not set", kernel was not compiled with support
```

If not compiled, must use Option 1 (kernel rebuild).

### iptables-legacy switch fails

**Symptom:** `update-alternatives` command not found or fails

**Solution:** Verify iptables-legacy is installed:
```bash
pacman -Q iptables-legacy
# If not found:
sudo pacman -S iptables-legacy
```

### Performance issues after fix

**Symptom:** Docker works but noticeably slow

**Solution:** If using Option 2 or 3, the issue is likely kernel-level overhead. Option 1 (proper kernel recompilation) resolves this.

## Long-term Recommendation

For production use, **always use Option 1** (kernel rebuild). It provides:
- Optimal performance
- Proper kernel integration
- Permanent fix (no reboots needed)
- Official support and updates

## References

- [Arch Linux Netfilter Documentation](https://wiki.archlinux.org/title/Iptables)
- [Netfilter Project Documentation](https://www.netfilter.org/)
- [Docker Networking Documentation](https://docs.docker.com/engine/tutorials/networkingcontainers/)
- [CachyOS Kernel Compilation](https://wiki.archlinux.org/title/Kernel/Compilation)

