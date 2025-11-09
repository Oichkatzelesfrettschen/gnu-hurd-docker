# GNU/Hurd Docker - Complete Interactive Access Guide

**Last Updated:** 2025-11-06
**Status:** Comprehensive documentation of all access methods
**Purpose:** Enable successful interaction with GNU/Hurd running in QEMU/Docker

---

## Executive Summary

The official Debian GNU/Hurd image (debian-hurd-i386-20250807.img) **does NOT** include SSH server by default. To enable SSH access, you must first access the system via serial console, then manually install and configure OpenSSH.

**Access Methods Available:**
1. ✅ **Serial Console (telnet)** - PRIMARY method for initial setup
2. ❌ **SSH** - NOT available until installed via serial console
3. ✅ **VNC** - Available if DISPLAY_MODE=vnc
4. ✅ **QEMU Monitor** - Available for VM control
5. ✅ **QMP (QEMU Machine Protocol)** - Available for automation

---

## Method 1: Serial Console Access (PRIMARY)

### Quick Start

```bash
# Connect to serial console
telnet localhost 5555

# At login prompt:
# Username: root
# Password: (press Enter - empty password by default)
```

### Configuration in entrypoint.sh

Line 215:
```bash
-serial telnet:0.0.0.0:5555,server,nowait
```

This creates a telnet server on port 5555 that provides access to the GNU/Hurd serial console.

### Manual Interaction

```bash
# 1. Connect
telnet localhost 5555

# 2. Wait for login prompt (may take 2-3 minutes after QEMU starts)
# You should see:
#   Debian GNU/Hurd localhost tty1
#   localhost login:

# 3. Login as root
root
(press Enter for password)

# 4. You're now at the Hurd shell!
root@localhost:~#
```

### Troubleshooting Serial Console

**Problem:** Connection accepted but no output
**Solution:** The system may still be booting. GNU/Hurd first boot takes 3-5 minutes. Press Enter a few times to trigger output.

**Problem:** "Connection refused"
**Solution:** QEMU hasn't started yet or port 5555 is in use. Check:
```bash
ss -tln | grep 5555
docker logs gnu-hurd-dev
```

**Problem:** Garbled output
**Solution:** Terminal settings issue. Try:
```bash
export TERM=vt100
telnet localhost 5555
```

---

## Method 2: SSH Access (Requires Installation)

### Current Status

❌ **SSH is NOT pre-installed in the Debian GNU/Hurd image**

### Installation Required

You must install SSH via serial console first:

```bash
# 1. Access via serial console (Method 1 above)
telnet localhost 5555
# Login as root

# 2. Update package lists
apt-get update

# 3. Install SSH server and entropy daemon (CRITICAL)
apt-get install -y openssh-server random-egd

# 4. Start SSH daemon
/etc/init.d/ssh start

# 5. Enable SSH on boot
update-rc.d ssh defaults

# 6. Set root password (security)
passwd root
```

### Why random-egd is Required

GNU/Hurd lacks hardware entropy sources (`/dev/random`). The `random-egd` package provides:
- Entropy Gathering Daemon (EGD)
- Emulated /dev/random using software entropy collection
- **Critical for SSH key generation and encryption**

Without `random-egd`, SSH will fail to start due to inability to generate host keys.

### Automated Installation Script

We provide an automated script that handles SSH installation:

```bash
./scripts/install-ssh-hurd.sh
```

This script:
1. Connects to serial console via telnet
2. Logs in as root (empty password)
3. Installs openssh-server and random-egd
4. Starts SSH daemon
5. Sets root password to "root" (change after first login!)

### Testing SSH After Installation

```bash
# Test SSH connectivity
ssh -p 2222 root@localhost

# Or with password automation
sshpass -p "root" ssh -p 2222 root@localhost "uname -a"
```

Expected output:
```
GNU localhost 0.9 GNU-Mach 1.8+git20230520-486/Hurd-0.9 i686-AT386
```

---

## Method 3: VNC Access

### Configuration

Set environment variable before starting container:

```bash
# In docker-compose.override.yml
environment:
  - DISPLAY_MODE=vnc
  - QEMU_VIDEO=std

# Or via docker run
docker run -e DISPLAY_MODE=vnc ...
```

### Connecting

```bash
# VNC is exposed on port 5901
vncviewer localhost:5901

# Or use any VNC client
# Server: localhost:5901
# No password required (adjust QEMU -vnc options for password)
```

### Advantages
- Full graphical interface
- Mouse and keyboard interaction
- See boot process visually
- Better for debugging display issues

### Disadvantages
- Higher resource usage
- Requires VNC client installed
- Network bandwidth for display data

---

## Method 4: QEMU Monitor

### Purpose

The QEMU Monitor provides VM control capabilities:
- Pause/resume VM
- Create/load snapshots
- Inspect VM state
- Hot-plug devices
- Debug guest issues

### Connecting

```bash
# Connect via socat
docker exec -it gnu-hurd-dev socat - UNIX-CONNECT:/qmp/monitor.sock

# Or via script
./scripts/connect-console.sh --monitor
```

### Useful Commands

```
(qemu) info status          # Show VM running state
(qemu) info qtree           # Show device tree
(qemu) info network         # Show network configuration
(qemu) stop                 # Pause VM
(qemu) cont                 # Resume VM
(qemu) savevm snapshot1     # Create snapshot
(qemu) loadvm snapshot1     # Load snapshot
(qemu) quit                 # Shutdown QEMU (clean)
```

### Monitoring Boot Progress

```bash
# Check if VM is running
echo "info status" | socat - UNIX-CONNECT:/qmp/monitor.sock

# Expected output:
# VM status: running
```

---

## Method 5: QMP (QEMU Machine Protocol)

### Purpose

JSON-based protocol for programmatic VM control. Used for automation and monitoring.

### Configuration

Line 214 in entrypoint.sh:
```bash
-qmp unix:/qmp/qmp.sock,server,nowait
```

### Usage Example

```bash
# Query VM status
echo '{"execute":"qmp_capabilities"}' | socat - UNIX-CONNECT:/qmp/qmp.sock
echo '{"execute":"query-status"}' | socat - UNIX-CONNECT:/qmp/qmp.sock

# Response:
# {"return":{"running":true,"singlestep":false,"status":"running"}}
```

### Python Helper

We provide `scripts/qmp-helper.py` for easier QMP interaction:

```bash
# Query status
echo '{"execute":"query-status"}' | python3 scripts/qmp-helper.py

# Query block devices
echo '{"execute":"query-block"}' | python3 scripts/qmp-helper.py
```

---

## Complete Workflow: From Boot to SSH Access

### Step 1: Start Container

```bash
# Using docker-compose
docker-compose up -d

# Or with custom display mode
DISPLAY_MODE=nographic docker-compose up -d
```

### Step 2: Wait for Boot (3-5 minutes)

```bash
# Monitor container logs
docker-compose logs -f

# Check QEMU process
docker exec gnu-hurd-dev ps aux | grep qemu

# Verify VM is running
echo "info status" | docker exec -i gnu-hurd-dev socat - UNIX-CONNECT:/qmp/monitor.sock
```

### Step 3: Access via Serial Console

```bash
# Connect
telnet localhost 5555

# Wait for login prompt (may need to press Enter a few times)
# Login: root
# Password: (press Enter)
```

### Step 4: Verify Network

```bash
# Inside Hurd shell
# Check network interface
settrans -p /servers/socket/2

# Should show:
# /hurd/pfinet --interface=/dev/eth0 --address=10.0.2.15 ...

# Test connectivity
ping -c 3 8.8.8.8
```

### Step 5: Install SSH

```bash
# Update packages
apt-get update

# Install SSH and entropy daemon
apt-get install -y openssh-server random-egd

# Start SSH
/etc/init.d/ssh start

# Enable on boot
update-rc.d ssh defaults
```

### Step 6: Test SSH

```bash
# From host
ssh -p 2222 root@localhost

# Should prompt for password (press Enter)
# You're now connected via SSH!
```

### Step 7: Secure the System

```bash
# Set strong root password
passwd root

# Create non-root user
useradd -m -s /bin/bash youruser
passwd youruser
```

---

## Comparison: Access Methods

| Method | Pre-installed | Best For | Boot Required | Network Required |
|--------|---------------|----------|---------------|------------------|
| Serial Console | ✅ Yes | Initial setup, debugging | No (see BIOS/bootloader) | No |
| SSH | ❌ No (must install) | Remote access, automation | Yes (full boot) | Yes |
| VNC | ✅ Yes (if configured) | Visual debugging, GUI | No (see boot process) | No (local) |
| QEMU Monitor | ✅ Yes | VM control, snapshots | No | No |
| QMP | ✅ Yes | Automation, monitoring | No | No |

---

## Common Issues and Solutions

### Issue: "No login prompt after 5 minutes"

**Possible Causes:**
1. System is still booting (Hurd can take 5-10 minutes on first boot)
2. Bootloader waiting for input
3. System hung

**Solutions:**
```bash
# 1. Check VM is actually running
docker exec gnu-hurd-dev ps aux | grep qemu

# 2. Connect to serial and press Enter several times
telnet localhost 5555
(press Enter multiple times)

# 3. Check for errors in QEMU log
docker exec gnu-hurd-dev cat /tmp/qemu.log

# 4. Restart with VNC to see what's happening
docker-compose down
DISPLAY_MODE=vnc docker-compose up -d
vncviewer localhost:5901
```

### Issue: "SSH connection refused"

**Diagnosis:**
```bash
# From inside serial console:
/etc/init.d/ssh status

# Should show:
# sshd is running
```

**If not running:**
```bash
# Start SSH manually
/etc/init.d/ssh start

# Check for errors
journalctl -xe
# (Note: Hurd uses sysvinit, not systemd)
```

### Issue: "SSH connection timeout"

**Possible Causes:**
1. Port forwarding not working
2. Firewall blocking port 2222
3. SSH not listening on correct interface

**Solutions:**
```bash
# 1. Verify port forwarding (from host)
ss -tln | grep 2222

# 2. Check QEMU network config (from inside Hurd)
ifconfig /dev/eth0

# 3. Verify SSH is listening
netstat -tlnp | grep sshd
```

### Issue: "random-egd not installed, SSH fails to start"

**Symptoms:**
```
sshd: Could not load host key: /etc/ssh/ssh_host_rsa_key
sshd: Could not load host key: /etc/ssh/ssh_host_ecdsa_key
sshd: fatal: No host keys available
```

**Solution:**
```bash
# Install entropy daemon
apt-get install -y random-egd

# Regenerate host keys
rm /etc/ssh/ssh_host_*
dpkg-reconfigure openssh-server

# Restart SSH
/etc/init.d/ssh restart
```

---

## Performance Expectations

### Boot Times
- First boot: 5-10 minutes (filesystem init, translator setup)
- Subsequent boots: 2-3 minutes
- With KVM: 2-3 minutes (50% faster)

### SSH Connection
- Initial connection: 1-2 seconds
- Command execution: 100-200ms overhead (microkernel IPC)
- File transfer: 5-10 MB/s (QEMU user-mode network)

### Serial Console
- Response time: Instant (direct QEMU serial)
- Reliability: 100% (always available)
- Best for: Initial setup, debugging

---

## Automation Scripts

### scripts/install-ssh-hurd.sh

Automated SSH installation via serial console. Uses expect to:
1. Connect to telnet
2. Login as root
3. Install packages
4. Configure SSH
5. Set password

```bash
./scripts/install-ssh-hurd.sh
```

### scripts/connect-console.sh

Smart console connector that detects PTY or uses telnet:

```bash
# Connect to serial console
./scripts/connect-console.sh

# Connect to QEMU monitor
./scripts/connect-console.sh --monitor

# Show logs with PTY info
./scripts/connect-console.sh --logs
```

### scripts/test-hurd-system.sh

Comprehensive system testing via SSH:

```bash
./scripts/test-hurd-system.sh
```

Tests:
- Container running
- SSH connectivity
- User accounts (root, agents)
- C compilation
- Package management
- Filesystem operations

---

## Security Considerations

### Default Credentials

❗ **SECURITY WARNING:** The Debian GNU/Hurd image has:
- Root user with **empty password**
- Demo user with **empty password**

**Immediate Actions Required:**
```bash
# Set root password
passwd root

# Disable demo user or set password
passwd demo
# or
userdel -r demo
```

### SSH Hardening

After SSH is working, harden the configuration:

```bash
# Edit SSH config
nano /etc/ssh/sshd_config

# Recommended changes:
PermitRootLogin no                    # Disable direct root login
PasswordAuthentication no             # Use keys only
PubkeyAuthentication yes              # Enable key-based auth
Port 22                                # Keep default (forwarded by QEMU)

# Restart SSH
/etc/init.d/ssh restart
```

### Firewall (if enabled)

GNU/Hurd supports basic packet filtering:

```bash
# No iptables by default (minimalist system)
# Consider limiting services instead
```

---

## References

1. **Debian GNU/Hurd Documentation**
   - https://www.debian.org/ports/hurd/
   - https://www.debian.org/ports/hurd/hurd-install

2. **GNU Hurd Project**
   - https://www.gnu.org/software/hurd/
   - https://www.gnu.org/software/hurd/hurd/documentation.html

3. **OpenSSH on GNU/Hurd**
   - OpenSSH 9.9+ includes official Hurd support
   - https://www.openssh.com/releasenotes.html

4. **QEMU Serial Console**
   - https://qemu.readthedocs.io/en/latest/system/invocation.html#hxtool-5

5. **QEMU QMP Protocol**
   - https://qemu.readthedocs.io/en/latest/interop/qmp-spec.html

6. **Project Documentation**
   - SSH-CONFIGURATION-RESEARCH.md (detailed research)
   - HURD-TESTING-REPORT.md (test results)
   - QEMU-OPTIMIZATION-2025.md (performance tuning)

---

## Next Steps

1. ✅ Access via serial console
2. ✅ Install SSH server (openssh-server + random-egd)
3. ✅ Configure network (if needed)
4. ✅ Test SSH connectivity
5. ✅ Secure the system (passwords, SSH hardening)
6. 📝 Document your setup in project-specific docs
7. 🚀 Start developing on GNU/Hurd!

---

**End of Interactive Access Guide**
