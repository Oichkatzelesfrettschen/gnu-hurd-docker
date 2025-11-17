# GNU/Hurd Docker - Common Issues and Solutions

**Last Updated**: 2025-11-07
**Consolidated From**:
- TROUBLESHOOTING.md (general issues)
- VALIDATION-AND-TROUBLESHOOTING.md (kernel fix)
- IO-ERROR-FIX.md (x86_64 storage fix)

**Purpose**: Complete troubleshooting reference for common issues

**Scope**: Debian GNU/Hurd x86_64 only (i386 deprecated 2025-11-07)

---

## Quick Diagnostic Commands

Before diving into specific issues, run these commands to gather information:

```bash
# System status
docker ps -a
docker-compose ps
docker-compose logs --tail=50

# Resource usage
docker stats gnu-hurd-x86_64
df -h /
free -h

# Network connectivity
ping 8.8.8.8
nc -zv localhost 2222  # SSH port test

# QEMU process status
ps aux | grep qemu-system-x86_64

# Image integrity
qemu-img check debian-hurd-amd64-80gb.qcow2
```

---

## Hardware Limitations and Known Issues

### Overview

Debian GNU/Hurd 2025 has specific hardware limitations due to missing drivers and microkernel architecture constraints.

### Supported Hardware

✅ **What Works**:
- SATA/AHCI disks (in AHCI mode, NOT RAID)
- E1000 and compatible Ethernet NICs
- PS/2 keyboards and mice
- VGA/VESA graphics (no 3D acceleration)
- Serial ports (for console)
- PC speaker (basic beep)

### Unsupported Hardware

❌ **What Doesn't Work**:
- **USB Devices**: NO USB HID support (no USB keyboards/mice)
- **Wireless Networking**: NO WiFi support
- **Sound Cards**: NO audio drivers yet
- **Non-Free Firmware**: NO firmware loading support
- **Thunderbolt/Firewire**: Not supported
- **Modern NVMe**: Limited support (use AHCI SATA instead)
- **RAID Controllers**: Must use AHCI mode, NOT hardware RAID

### Virtual Machine Specific

#### QEMU/KVM (Recommended)

✅ **Recommended Settings**:
```bash
qemu-system-x86_64 \
    -m 2G \                              # 2-8GB RAM
    -smp cores=2 \                       # 1-2 CPUs (stable)
    -drive file=hurd.img,cache=writeback \  # SATA/AHCI
    -net nic,model=e1000 \               # E1000 NIC
    -net user \                          # User-mode networking
    -vga std                             # Standard VGA
```

❌ **Avoid**:
- More than 2 CPUs (SMP experimental)
- virtio drivers (not fully supported)
- USB devices (USB HID not supported)
- q35 machine type (use 'pc' instead)

#### VirtualBox (Less Tested)

✅ **Required Settings**:
```bash
# Enable HPET (REQUIRED!)
VBoxManage modifyvm "Hurd VM" --hpet on

# Other settings
- CPU: 1 core (SMP causes crashes)
- RAM: 2GB minimum, 4GB recommended
- Disk: IDE or SATA (AHCI mode)
- Network: Intel PRO/1000 MT or AMD PCnet
- Input: PS/2 only (disable USB tablet!)
- Graphics: VBoxVGA or VMSVGA
```

❌ **Common VirtualBox Issues**:
- **No HPET**: Timer issues, system instability
- **USB Input**: System won't recognize keyboard/mouse
- **SMP > 1**: Crashes, kernel panics, deadlocks
- **SATA (RAID mode)**: Boot failures, disk not found

### Filesystem Limitations

⚠️ **Important**:
- **ext2 only**: Hurd uses ext2 (with xattr for translators)
- **No separate /usr**: /usr or /usr/local on separate partition NOT supported
- **Proper shutdown required**: ext2 is fragile - always shutdown cleanly!
- **fsck on crashes**: After crashes, may need manual fsck

**Safe shutdown**:
```bash
# Inside Hurd
sudo poweroff

# Or from host
ssh -p 2222 root@localhost "shutdown -h now"
```

### Performance Expectations

⚠️ **Realistic Performance**:
- **Boot Time**: 30-60s with KVM, 3-5min with TCG emulation
- **Package Installation**: Slower than Linux (apt may take longer)
- **GUI Performance**: Usable but not optimized (LXDE recommended)
- **Compilation**: Slower than Linux (use -j1 or -j2 for make)

### Network Limitations

⚠️ **Network Issues**:
- **No WiFi**: Ethernet only (wired or emulated)
- **Limited Protocols**: Standard TCP/IP works, advanced features may not
- **DHCP**: Works in QEMU/VirtualBox user-mode networking
- **Static IP**: Supported but requires manual configuration

### Development Limitations

⚠️ **For Developers**:
- **strace doesn't exist**: Use `trace` for RPC tracing instead
- **systemd not available**: Init scripts only
- **Limited procfs**: Basic /proc exists but minimal
- **No cgroups**: Process control different from Linux

### Workarounds

#### No Sound?
**Workaround**: None currently. Sound drivers not implemented yet.

#### No USB keyboard?
**Workaround**: Use PS/2 emulation in QEMU/VirtualBox.

```bash
# QEMU automatically provides PS/2
# VirtualBox: Disable "USB tablet" in VM settings
```

#### Wireless needed?
**Workaround**: Use Ethernet or USB-to-Ethernet adapter on host, pass through as E1000 to guest.

#### System crashes frequently?
**Workarounds**:
1. Reduce CPUs to 1 (disable SMP)
2. Use 'pc' machine type, not 'q35'
3. Enable proper shutdown, never force kill
4. Use snapshots before risky operations

---

## Docker Daemon Issues

### Docker Daemon Won't Start

**Error**: `daemon is not responding` or `Cannot connect to Docker daemon`

**Root Cause**: Docker service not running or kernel networking issue

**Solutions**:

```bash
# Check Docker service status
sudo systemctl status docker

# Start Docker service
sudo systemctl start docker

# Enable on boot
sudo systemctl enable docker

# Check Docker logs for errors
sudo journalctl -u docker -n 100

# Verify Docker can run
docker ps

# If permission denied, add user to docker group
sudo usermod -aG docker $USER
newgrp docker
```

**Advanced**: If Docker fails with `CHAIN_ADD failed (No such file or directory)`:

This indicates kernel nf_tables networking issue. See [Kernel Networking Fix](#kernel-networking-fix) below.

---

### Kernel Networking Fix (nf_tables)

**Error**: Docker daemon logs show:

```
CHAIN_ADD failed (No such file or directory): chain PREROUTING
iptables v1.8.11 (nf_tables): CHAIN_ADD failed
```

**Root Cause**: Linux kernel nf_tables subsystem not properly initialized with NAT chains.

**This is a system-level kernel issue**, not a Docker configuration problem.

**Three Solutions** (choose one):

#### Solution 1: Load nf_tables Modules (Quick Fix)

**Time**: 30 seconds
**Persistence**: Requires configuration to survive reboot

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

# Restart Docker
sudo systemctl restart docker

# Test Docker
docker ps
```

**Make Permanent**:

```bash
# Create module load file
sudo tee /etc/modules-load.d/docker.conf << 'EOF'
nf_tables
nf_tables_ipv4
nft_masq
nf_nat
EOF

# Verify after reboot
sudo reboot
# After reboot: lsmod | grep nf_tables
```

#### Solution 2: Switch to iptables-legacy (Temporary)

**Time**: 1 minute
**Persistence**: Survives reboots

```bash
# Install iptables-legacy
sudo pacman -S iptables-legacy

# Switch to legacy mode
sudo update-alternatives --set iptables /usr/bin/iptables-legacy
sudo update-alternatives --set ip6tables /usr/bin/ip6tables-legacy

# Verify switch
ls -la /usr/bin/iptables | grep iptables

# Restart Docker
sudo systemctl restart docker

# Test Docker
docker ps
```

**Revert to nftables**:

```bash
sudo update-alternatives --set iptables /usr/bin/iptables-nft
sudo update-alternatives --set ip6tables /usr/bin/ip6tables-nft
sudo systemctl restart docker
```

#### Solution 3: Rebuild Kernel (Long-term, Advanced)

**Time**: 2-3 hours
**Persistence**: Permanent fix

**Prerequisites**:
- 10 GB free disk space
- Build tools: `base-devel`, `linux-headers`

```bash
# Install dependencies
sudo pacman -S base-devel linux-headers

# Clone kernel sources (CachyOS)
git clone https://github.com/CachyOS/linux-cachyos
cd linux-cachyos

# Copy current config
cp /proc/config.gz ./
gunzip config.gz
mv config .config

# Enable required options:
make menuconfig
# Navigate to: Networking > Netfilter Configuration
# Enable:
#   CONFIG_NETFILTER=y
#   CONFIG_NETFILTER_XTABLES=y
#   CONFIG_NF_NAT=y
#   CONFIG_NETFILTER_XT_TARGET_MASQUERADE=y
#   CONFIG_NF_TABLES=y
#   CONFIG_NF_TABLES_IPV4=y
#   CONFIG_NF_TABLES_NAT=y
#   CONFIG_NF_NAT_IPV4=y

# Build and install (use CPU core count for --jobs)
time makepkg -fsi --jobs=4

# Reboot to new kernel
sudo reboot
```

**Verification**:

```bash
# Check kernel config
zgrep CONFIG_NF_TABLES /proc/config.gz
# Should show: CONFIG_NF_TABLES=m or =y

# Test Docker
docker ps
```

**Recommendation**: Use Solution 1 for development, Solution 3 for production.

---

### Permission Denied Errors

**Error**: `permission denied while trying to connect to Docker daemon socket`

**Root Cause**: User not in `docker` group

**Solutions**:

```bash
# Add user to docker group
sudo usermod -aG docker $USER

# Apply group changes (no logout required)
newgrp docker

# Verify Docker socket permissions
ls -la /var/run/docker.sock
# Should show: srw-rw---- 1 root docker

# Test Docker access
docker ps
```

**If still failing**:

```bash
# Check Docker socket ownership
sudo chown root:docker /var/run/docker.sock

# Restart Docker daemon
sudo systemctl restart docker
```

---

## Image and Container Issues

### Image Build Fails

**Error**: `docker-compose build` fails with errors

**Causes and Solutions**:

**1. Insufficient Disk Space**:

```bash
# Check available space (need 10 GB+ free)
df -h /

# Clean Docker cache
docker system prune -af

# Remove unused images
docker image prune -af
```

**2. Network Connectivity Issues**:

```bash
# Test connectivity
ping 8.8.8.8
ping deb.debian.org

# Check DNS
cat /etc/resolv.conf

# Test package mirrors
curl -I https://deb.debian.org
```

**3. Dockerfile Syntax Errors**:

```bash
# Validate Dockerfile
docker build --dry-run .

# Build with detailed output
docker-compose build --progress=plain

# Build without cache
docker-compose build --no-cache
```

---

### Container Won't Start

**Error**: `docker-compose up -d` fails or container exits immediately

**Diagnostic Steps**:

```bash
# 1. Check logs
docker-compose logs --tail=100

# 2. Verify QCOW2 image exists
ls -lh debian-hurd-amd64-80gb.qcow2

# 3. Check volume mount paths
grep -A 3 "volumes:" docker-compose.yml

# 4. Try interactive mode to see errors
docker-compose up
# Press Ctrl+C to stop

# 5. Check container status
docker ps -a | grep gnu-hurd

# 6. Remove failed container and retry
docker-compose down -v
docker-compose up -d
```

**Common Issues**:

**Missing QCOW2 image**:

```bash
# Download x86_64 image
./scripts/setup-hurd-amd64.sh
```

**Entrypoint script errors**:

```bash
# Validate entrypoint.sh
shellcheck entrypoint.sh

# Check permissions
chmod +x entrypoint.sh
```

**Image corruption**:

```bash
# Check image integrity
qemu-img check debian-hurd-amd64-80gb.qcow2

# Repair if needed
qemu-img check -r all debian-hurd-amd64-80gb.qcow2
```

---

### Container Exits Immediately

**Error**: `docker-compose ps` shows `Exited (1)` or `Exited (137)`

**Exit Code Meanings**:
- `Exited (1)`: General error in entrypoint script or QEMU
- `Exited (137)`: Killed by system (OOM killer or manual kill)

**Solutions**:

```bash
# View exit logs
docker-compose logs --tail=50

# Check entrypoint.sh for syntax errors
shellcheck entrypoint.sh

# Verify image built successfully
docker image ls | grep gnu-hurd

# Check QEMU command line
docker-compose logs | grep "qemu-system"

# Try rebuilding image
docker-compose build --no-cache
docker-compose up -d
```

**If OOM (Out of Memory) killed container**:

```bash
# Check Docker events
docker events | grep -E "kill|oom"

# Reduce QEMU RAM allocation
# Edit docker-compose.yml:
environment:
  QEMU_RAM: 2048  # Reduced from 4096

# Or check host memory
free -h
```

---

### Port Conflicts

**Error**: `Ports are not available; port 2222 is already allocated`

**Solutions**:

```bash
# Check what's using port 2222
lsof -i :2222
# or
ss -tlnp | grep 2222

# Stop conflicting service
sudo systemctl stop <service>

# Or use different host port in docker-compose.yml
# Change: "2222:22" to "2223:22"
ports:
  - "2223:22"   # SSH (host:container)
  - "8080:80"   # HTTP

# Then restart
docker-compose down
docker-compose up -d

# Connect via new port
ssh -p 2223 root@localhost
```

---

## QEMU and GNU/Hurd Issues

### QEMU Hangs During Boot

**Symptom**: QEMU starts but system doesn't boot past GRUB or kernel

**Causes**:
1. GRUB waiting for input
2. Slow TCG emulation (without KVM)
3. Storage interface incompatibility

**Solutions**:

**1. GRUB waiting for input**:

```bash
# Connect to serial console
telnet localhost 5555

# Press Enter several times to select default boot
# (GRUB may have 5-10 second timeout)
```

**2. Slow TCG (without KVM)**:

```bash
# Check if KVM is available
ls -la /dev/kvm

# If missing, boot will be slow (5-10 minutes is normal)
# Monitor boot progress
docker-compose logs -f | grep -E "boot|grub|kernel"

# Or increase timeout expectations
# x86_64 + TCG: 10-15 minutes to SSH
# x86_64 + KVM: 5-10 minutes to SSH
```

**3. Storage interface incompatibility** (x86_64 specific):

```bash
# Check current storage interface
grep QEMU_STORAGE docker-compose.yml

# x86_64 Hurd prefers SATA over IDE
# Edit docker-compose.yml:
environment:
  QEMU_STORAGE: sata  # Not ide
  QEMU_EXTRA_ARGS: "-cpu host -machine type=pc,accel=kvm:tcg"

# Rebuild and restart
docker-compose down
docker-compose build
docker-compose up -d
```

**Rationale**: The official x86_64 Hurd image has better SATA/AHCI support than IDE. Q35 machine type may also cause issues; use `pc` instead.

---

### I/O Errors at Boot (x86_64 Specific)

**Error**: Console shows:

```
ext2fs: part:1:device:wd0: Input/output error
```

**Root Cause**: IDE storage interface incompatible with x86_64 Hurd + Q35 machine type.

**Solution**: Switch to SATA storage and PC machine type.

**Edit docker-compose.yml**:

**Before** (IDE with Q35):
```yaml
environment:
  QEMU_STORAGE: ide
  QEMU_EXTRA_ARGS: "-cpu host,+svm,+vmx -machine type=q35,accel=kvm:tcg"
```

**After** (SATA with PC):
```yaml
environment:
  QEMU_STORAGE: sata
  QEMU_EXTRA_ARGS: "-cpu host -machine type=pc,accel=kvm:tcg"
```

**Changes**:
1. Storage: `ide` → `sata` (SATA/AHCI controller)
2. Machine: `q35` → `pc` (standard PC platform)
3. CPU flags: Removed `+svm,+vmx` (not needed)

**Rebuild and test**:

```bash
docker-compose down
docker-compose build
docker-compose up -d

# Monitor boot
docker-compose logs -f
```

**Expected**: No I/O errors, disk detected as SATA device (sd0).

---

### Serial Console Not Responding

**Error**: Serial console connects but no input accepted

**Solutions**:

```bash
# 1. Find correct serial port
docker-compose logs | grep "char device redirected"

# 2. Try pressing Enter to wake console
telnet localhost 5555
# Press: Enter, Enter, Enter

# 3. Check if QEMU serial is configured correctly
docker-compose logs | grep -E "serial|monitor"

# 4. Verify entrypoint.sh has correct serial setup
grep "serial" entrypoint.sh
# Should have: -serial telnet:0.0.0.0:5555,server,nowait

# 5. If corrupted, reconnect
# Press Ctrl+] to enter telnet command mode
quit
# Then reconnect
telnet localhost 5555
```

---

### Container Consumes Too Much Memory

**Error**: Container using more than expected memory

**Check current usage**:

```bash
docker stats gnu-hurd-x86_64
```

**Solutions**:

```bash
# 1. Reduce QEMU memory allocation
# Edit docker-compose.yml:
environment:
  QEMU_RAM: 2048  # Reduce from 4096 or 8192

# 2. Check QEMU process inside container
docker-compose exec gnu-hurd-x86_64 ps aux | grep qemu

# 3. Check host memory
free -h

# 4. Inside guest, clean up packages
docker-compose exec gnu-hurd-x86_64 bash
apt-get clean
apt-get autoremove
```

---

## Disk and Storage Issues

### Disk Image Corrupted

**Error**: QEMU refuses to boot from QCOW2 or shows errors

**Diagnostic**:

```bash
# Check QCOW2 integrity
qemu-img check debian-hurd-amd64-80gb.qcow2

# Output may show:
# - "No errors were found" (good)
# - "X errors were found" (needs repair)
```

**Solutions**:

**1. Repair QCOW2**:

```bash
# Create backup first
cp debian-hurd-amd64-80gb.qcow2 debian-hurd-amd64-80gb.qcow2.backup

# Repair (use '-r all' for aggressive repair)
qemu-img check -r all debian-hurd-amd64-80gb.qcow2

# Test boot
docker-compose up -d
```

**2. Convert and Reconvert** (if repair fails):

```bash
# Convert to raw
qemu-img convert -f qcow2 -O raw \
    debian-hurd-amd64-80gb.qcow2 \
    temp.img

# Convert back to qcow2
qemu-img convert -f raw -O qcow2 \
    temp.img \
    debian-hurd-amd64-80gb.qcow2

# Remove temp file
rm temp.img

# Test boot
docker-compose up -d
```

**3. Restore from Backup or Re-download**:

```bash
# If repair fails, restore backup
cp debian-hurd-amd64-80gb.qcow2.backup debian-hurd-amd64-80gb.qcow2

# Or re-download fresh image
./scripts/setup-hurd-amd64.sh
# Note: This overwrites existing image
```

---

### Disk Space Running Out

**Error**: System runs out of disk space

**Inside Guest**:

```bash
# Check disk usage
docker-compose exec gnu-hurd-x86_64 df -h

# Clean package cache
docker-compose exec gnu-hurd-x86_64 apt-get clean
docker-compose exec gnu-hurd-x86_64 apt-get autoremove

# Find large files
docker-compose exec gnu-hurd-x86_64 du -sh /* | sort -rh

# Clean log files
docker-compose exec gnu-hurd-x86_64 rm -f /var/log/*.log
docker-compose exec gnu-hurd-x86_64 journalctl --vacuum-size=50M
```

**On Host**:

```bash
# Check host disk usage
df -h /

# Remove old backups
rm -f debian-hurd-amd64-80gb.qcow2.backup
rm -f debian-hurd-amd64-20251105.img.tar.xz

# Clean Docker system
docker system prune -af
```

---

## Performance Issues

### System Very Slow

**Symptoms**: Commands take minutes to execute, boot takes > 30 minutes

**Causes**:
1. No KVM (using TCG software emulation)
2. Insufficient host resources
3. Too many background services

**Diagnostic**:

```bash
# Check if KVM is available
ls -la /dev/kvm

# Check CPU usage inside container
docker-compose exec gnu-hurd-x86_64 top

# Monitor host CPU usage
top
# Look for qemu-system-x86_64 process

# Check disk I/O (if iostat available)
docker-compose exec gnu-hurd-x86_64 iostat -x 1 5
```

**Solutions**:

**1. Enable KVM** (Linux hosts only):

```yaml
# docker-compose.yml
devices:
  - /dev/kvm:/dev/kvm:rw
```

**2. Reduce background processes inside guest**:

```bash
# List running services
docker-compose exec gnu-hurd-x86_64 systemctl list-units --type=service --state=running

# Disable unnecessary services
docker-compose exec gnu-hurd-x86_64 systemctl disable <service>
docker-compose exec gnu-hurd-x86_64 systemctl stop <service>
```

**3. Increase host system resources**:

```yaml
# docker-compose.yml
environment:
  QEMU_SMP: 4     # More CPUs
  QEMU_RAM: 8192  # More RAM
```

**4. Reduce QEMU overhead**:

```yaml
# Use minimal display mode
environment:
  DISPLAY_MODE: nographic
```

---

### High CPU Usage

**Symptom**: QEMU process consuming 100%+ CPU

**Causes**:
1. Runaway processes inside guest
2. TCG emulation overhead (no KVM)
3. Infinite loops in startup scripts

**Solutions**:

```bash
# Check QEMU CPU usage
docker stats gnu-hurd-x86_64

# Inside guest, find high-CPU processes
docker-compose exec gnu-hurd-x86_64 ps aux --sort=-%cpu | head -10

# Kill runaway processes
docker-compose exec gnu-hurd-x86_64 kill -9 <PID>

# Check for infinite loops in logs
docker-compose logs | grep -E "error|loop|retry" | tail -50

# Disable unnecessary services
docker-compose exec gnu-hurd-x86_64 systemctl disable <service>
```

---

## Network Issues

### Can't Access Container from Host

**Error**: Cannot connect to SSH port or other exposed ports

**Diagnostic**:

```bash
# Verify port mapping
docker-compose ps

# Test SSH port on localhost
nc -zv localhost 2222      # Should succeed
telnet localhost 2222      # Should connect

# Check container network
docker inspect gnu-hurd-x86_64 | grep -A 10 "Networks"

# Check firewall on host
sudo ufw status

# If UFW enabled, allow ports
sudo ufw allow 2222
sudo ufw allow 8080
```

**Solutions**:

**1. Verify port mapping in docker-compose.yml**:

```yaml
ports:
  - "2222:22"   # SSH
  - "8080:80"   # HTTP
  - "5555:5555" # Serial console
```

**2. Check container is running**:

```bash
docker-compose ps
# Should show "Up" status
```

**3. Test from inside container**:

```bash
# Check if service is listening inside container
docker-compose exec gnu-hurd-x86_64 ss -tlnp | grep :22

# If not listening, start SSH
docker-compose exec gnu-hurd-x86_64 systemctl start ssh
```

---

### Container Can't Access External Network

**Error**: Cannot ping external hosts or resolve DNS inside guest

**Diagnostic**:

```bash
# Test connectivity inside container
docker-compose exec gnu-hurd-x86_64 ping -c 3 8.8.8.8

# Check routing
docker-compose exec gnu-hurd-x86_64 ip route show
# Should have default via 10.0.2.2 (QEMU user network)

# Check DNS resolution
docker-compose exec gnu-hurd-x86_64 cat /etc/resolv.conf
# Should have nameserver entries

# Test DNS
docker-compose exec gnu-hurd-x86_64 nslookup google.com
```

**Solutions**:

**1. Manually set DNS**:

```bash
docker-compose exec gnu-hurd-x86_64 bash
# Inside guest:
echo "nameserver 8.8.8.8" > /etc/resolv.conf
echo "nameserver 1.1.1.1" >> /etc/resolv.conf

# Test again
ping -c 3 google.com
```

**2. Check Docker network configuration**:

```bash
# List Docker networks
docker network ls

# Inspect Hurd network
docker network inspect hurd-net

# Verify bridge mode
grep "bridge" docker-compose.yml
```

**3. Check host firewall**:

```bash
# Allow Docker forwarding
sudo iptables -L -n | grep FORWARD
# FORWARD chain should allow traffic

# If blocked, check Docker iptables rules
sudo iptables -t nat -L -n
```

---

## General Troubleshooting Workflow

### Systematic Debugging

When encountering any issue, follow this workflow:

**1. Check Logs**:

```bash
# Container logs (last 100 lines)
docker-compose logs --tail=100

# Recent logs (last 10 minutes)
docker-compose logs --since 10m

# Follow logs in real-time
docker-compose logs -f

# Docker daemon logs
sudo journalctl -u docker -n 100
```

**2. Verify Resources**:

```bash
# Container resource usage
docker stats gnu-hurd-x86_64

# Host disk space
df -h /

# Host memory
free -h

# Check QCOW2 image size
ls -lh debian-hurd-amd64-80gb.qcow2
qemu-img info debian-hurd-amd64-80gb.qcow2
```

**3. Test Connectivity**:

```bash
# Container status
docker-compose ps

# Network connectivity inside container
docker-compose exec gnu-hurd-x86_64 ping -c 3 8.8.8.8

# SSH connectivity
ssh -p 2222 -o ConnectTimeout=5 root@localhost
```

**4. Check Service Status**:

```bash
# Inside container, check running services
docker-compose exec gnu-hurd-x86_64 systemctl status ssh
docker-compose exec gnu-hurd-x86_64 ps aux

# Check listening ports
docker-compose exec gnu-hurd-x86_64 ss -tlnp
```

**5. Rebuild and Restart**:

```bash
# Full cleanup and rebuild
docker-compose down -v
docker-compose build --no-cache
docker-compose up -d

# Monitor startup
docker-compose logs -f
```

---

## Getting Help

### Before Opening an Issue

1. **Check logs**: `docker-compose logs --tail=100`
2. **Verify configuration**: Run validation scripts
3. **Search documentation**: Check `docs/` folder and README.md
4. **Review this guide**: Most issues are documented here

### When Opening a GitHub Issue

Include:

1. **System information**:
   ```bash
   uname -a
   docker --version
   docker-compose --version
   qemu-system-x86_64 --version
   ```

2. **Error logs**:
   ```bash
   docker-compose logs --tail=200 > error-log.txt
   ```

3. **Configuration files**:
   - `docker-compose.yml`
   - `entrypoint.sh`
   - Relevant scripts

4. **Steps to reproduce**: Exact commands that trigger the issue

5. **Expected vs actual behavior**

---

## Reference Links

- **Docker Documentation**: https://docs.docker.com/
- **QEMU Documentation**: https://www.qemu.org/documentation/
- **GNU/Hurd Manual**: https://www.gnu.org/software/hurd/documentation.html
- **Debian GNU/Hurd**: https://www.debian.org/ports/hurd/
- **CachyOS Wiki**: https://wiki.archlinux.org/
- **Project Repository**: https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker

---

**Status**: Production Ready (x86_64-only)
**Last Updated**: 2025-11-07
**Architecture**: Pure x86_64
