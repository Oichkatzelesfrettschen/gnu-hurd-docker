# GNU/Hurd Docker - SSH Connection Issues

**Last Updated**: 2025-11-07
**Consolidated From**:
- TROUBLESHOOTING.md (SSH section)
- CI-CD-PROVISIONED-IMAGE.md (provisioning SSH)
- install-ssh-hurd.sh (automated installation)

**Purpose**: Diagnose and fix SSH connectivity problems

**Scope**: Debian GNU/Hurd x86_64 only (i386 deprecated 2025-11-07)

---

## Overview

SSH connectivity issues fall into three categories:

1. **SSH server not installed** (pre-provisioned images solve this)
2. **SSH server installed but not running** (service configuration)
3. **SSH server running but not accessible** (network/firewall issues)

**Default Credentials** (after provisioning):
- **Username**: `root`
- **Password**: `root` (change after first login!)

**Default Port Mapping**:
- **Host**: `localhost:2222`
- **Container**: Port 22 (standard SSH)

---

## Quick Diagnostic Workflow

Run these commands in order to identify the issue:

```bash
# 1. Check if container is running
docker-compose ps
# Expected: gnu-hurd-x86_64 in "Up" state

# 2. Test SSH port from host
nc -zv localhost 2222
# Expected: "Connection to localhost 2222 port [tcp/*] succeeded!"

# 3. Try SSH connection
ssh -p 2222 -o ConnectTimeout=5 root@localhost
# Expected: Password prompt or connection

# 4. If connection refused, check logs
docker-compose logs --tail=50 | grep -iE "ssh|sshd"

# 5. Inside container, check SSH service
docker-compose exec gnu-hurd-x86_64 systemctl status ssh
```

**Result**: This workflow identifies whether the issue is container, network, or SSH service.

---

## SSH Server Not Installed

### Symptom

```bash
ssh -p 2222 root@localhost
# ssh: connect to host localhost port 2222: Connection refused
```

**Inside container**:

```bash
docker-compose exec gnu-hurd-x86_64 which sshd
# which: no sshd in (...)
```

**Root Cause**: SSH server (`openssh-server`) not installed in guest.

---

### Solution 1: Use Pre-Provisioned Image

Download image with SSH already installed:

```bash
# Download pre-provisioned x86_64 image
curl -L "https://github.com/YOUR_ORG/gnu-hurd-docker/releases/download/v1.0.0-provisioned/debian-hurd-amd64-provisioned.qcow2.tar.gz" \
    -o provisioned.tar.gz

# Verify checksum
echo "YOUR_SHA256  provisioned.tar.gz" | sha256sum -c

# Extract
tar xzf provisioned.tar.gz

# Rename to expected path
mv debian-hurd-amd64-provisioned.qcow2 debian-hurd-amd64-80gb.qcow2

# Start VM
docker-compose up -d

# Wait for boot (5-10 minutes)
sleep 300

# SSH should work immediately
ssh -p 2222 root@localhost
```

**Benefit**: SSH pre-installed, no manual setup required.

---

### Solution 2: Install SSH via Serial Console

**Prerequisites**:
- Serial console accessible: `telnet localhost 5555`
- Network connectivity inside guest

**Manual Steps**:

```bash
# 1. Connect to serial console
telnet localhost 5555

# 2. Press Enter to get login prompt
# (may need several presses)

# 3. Login as root (password may be empty or "root")
login: root
Password: (try pressing Enter first, then "root" if needed)

# 4. Update package lists
apt-get update

# 5. Install SSH server and entropy daemon
apt-get install -y openssh-server random-egd

# 6. Start SSH service
systemctl start ssh
systemctl enable ssh

# 7. Set root password
passwd
# Enter new password twice

# 8. Configure SSH for password auth
sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config

# 9. Restart SSH
systemctl restart ssh

# 10. Exit serial console
exit

# 11. Test SSH from host
ssh -p 2222 root@localhost
```

**Time**: 10-15 minutes

---

### Solution 3: Automated Installation Script

**Use expect script** to automate serial console installation:

```bash
# Run automated SSH installation
export SERIAL_PORT=5555
export SERIAL_HOST=localhost
./scripts/install-ssh-hurd.sh

# Script will:
# 1. Connect to serial console
# 2. Login as root
# 3. Install openssh-server and random-egd
# 4. Configure SSH for password auth
# 5. Set root password to "root"
# 6. Start and enable SSH service
```

**Time**: 5-10 minutes

**See also**: `docs/05-CI-CD/PROVISIONED-IMAGE.md` for complete provisioning workflow.

---

## SSH Server Installed But Not Running

### Symptom

```bash
ssh -p 2222 root@localhost
# ssh: connect to host localhost port 2222: Connection refused
```

**Inside container**:

```bash
docker-compose exec gnu-hurd-x86_64 which sshd
# /usr/sbin/sshd (SSH is installed)

docker-compose exec gnu-hurd-x86_64 systemctl status ssh
# ● ssh.service - OpenBSD Secure Shell server
#    Loaded: loaded
#    Active: inactive (dead)
```

**Root Cause**: SSH service not started or crashed.

---

### Solution 1: Start SSH Service

```bash
# Inside container, start SSH
docker-compose exec gnu-hurd-x86_64 systemctl start ssh

# Enable on boot
docker-compose exec gnu-hurd-x86_64 systemctl enable ssh

# Verify running
docker-compose exec gnu-hurd-x86_64 systemctl status ssh
# Should show: Active: active (running)

# Check listening port
docker-compose exec gnu-hurd-x86_64 ss -tlnp | grep :22
# Should show: LISTEN ... :22
```

**Test**:

```bash
ssh -p 2222 root@localhost
```

---

### Solution 2: Check SSH Configuration

**If SSH fails to start**, check configuration errors:

```bash
# Test SSH config syntax
docker-compose exec gnu-hurd-x86_64 sshd -t

# Output:
# - No output: Config is valid
# - Error messages: Config has syntax errors

# View SSH config
docker-compose exec gnu-hurd-x86_64 cat /etc/ssh/sshd_config | grep -E "^[^#]"

# Check SSH logs
docker-compose exec gnu-hurd-x86_64 journalctl -u ssh -n 50
```

**Common Config Issues**:

**1. Port conflict**:

```bash
# sshd_config shows different port
Port 2222  # Should be Port 22 inside guest

# Fix:
docker-compose exec gnu-hurd-x86_64 \
    sed -i 's/^Port.*/Port 22/' /etc/ssh/sshd_config
docker-compose exec gnu-hurd-x86_64 systemctl restart ssh
```

**2. Root login disabled**:

```bash
# Check setting
docker-compose exec gnu-hurd-x86_64 \
    grep "PermitRootLogin" /etc/ssh/sshd_config

# Should be:
PermitRootLogin yes

# Fix if needed:
docker-compose exec gnu-hurd-x86_64 \
    sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
docker-compose exec gnu-hurd-x86_64 systemctl restart ssh
```

**3. Password authentication disabled**:

```bash
# Check setting
docker-compose exec gnu-hurd-x86_64 \
    grep "PasswordAuthentication" /etc/ssh/sshd_config

# Should be:
PasswordAuthentication yes

# Fix if needed:
docker-compose exec gnu-hurd-x86_64 \
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
docker-compose exec gnu-hurd-x86_64 systemctl restart ssh
```

---

## SSH Server Running But Not Accessible

### Symptom

```bash
docker-compose exec gnu-hurd-x86_64 systemctl status ssh
# Active: active (running)  <-- SSH is running

ssh -p 2222 root@localhost
# ssh: connect to host localhost port 2222: Connection refused
# OR: Connection timed out
```

**Root Cause**: Network or port forwarding issue.

---

### Solution 1: Verify Port Mapping

**Check docker-compose.yml**:

```yaml
ports:
  - "2222:22"   # Host port 2222 -> Container port 22
```

**Verify port mapping is active**:

```bash
docker-compose ps
# Should show: 0.0.0.0:2222->22/tcp

# Or use docker inspect
docker inspect gnu-hurd-x86_64 | grep -A 5 "PortBindings"
```

**If port mapping missing**:

```bash
# Fix docker-compose.yml and restart
docker-compose down
docker-compose up -d
```

---

### Solution 2: Check Host Firewall

**Test if port 2222 is blocked on host**:

```bash
# Check if port is open
nc -zv localhost 2222

# If blocked, check firewall
sudo ufw status
# If UFW enabled and blocking:
sudo ufw allow 2222
sudo ufw reload
```

**For other firewalls**:

```bash
# iptables
sudo iptables -L -n | grep 2222

# firewalld
sudo firewall-cmd --list-all | grep 2222
```

---

### Solution 3: Check QEMU User Network

**Inside container, verify QEMU network is configured**:

```bash
# Check QEMU is running with user network
docker-compose exec gnu-hurd-x86_64 ps aux | grep qemu

# Should show: -netdev user,id=net0,hostfwd=tcp::22-:22
```

**If hostfwd missing**, QEMU isn't forwarding SSH port:

**Check entrypoint.sh**:

```bash
grep "hostfwd" entrypoint.sh

# Should have:
-netdev user,id=net0,hostfwd=tcp::22-:22 \
-device e1000,netdev=net0
```

**If missing, add and rebuild**:

```bash
docker-compose down
docker-compose build
docker-compose up -d
```

---

### Solution 4: Inside Guest Network Check

**Verify SSH is listening inside guest**:

```bash
# Check SSH listening on port 22
docker-compose exec gnu-hurd-x86_64 ss -tlnp | grep :22
# Should show: LISTEN ... 0.0.0.0:22

# Check network interfaces
docker-compose exec gnu-hurd-x86_64 ip addr show
# Should have: eth0 with IP 10.0.2.15 (QEMU user network)

# Test SSH from inside container
docker-compose exec gnu-hurd-x86_64 ssh -p 22 root@localhost
# Should prompt for password (loopback test)
```

---

## SSH Connection Timeouts

### Symptom

```bash
ssh -p 2222 root@localhost
# (hangs for 30-60 seconds, then:)
# ssh: connect to host localhost port 2222: Connection timed out
```

**Root Cause**: System still booting or very slow.

---

### Solution: Wait for Boot Completion

**x86_64 boot times** (approximate):

| Configuration | Boot Time |
|---------------|-----------|
| KVM + SSD | 5-10 min |
| TCG + SSD | 10-15 min |
| TCG + HDD | 15-30 min |

**Monitor boot progress**:

```bash
# Watch logs in real-time
docker-compose logs -f | grep -E "boot|grub|ssh|login"

# Check for SSH start message
docker-compose logs | grep "Started OpenBSD Secure Shell server"
```

**Automated wait script**:

```bash
#!/bin/bash
for i in {1..120}; do
    echo "Attempt $i/120: Testing SSH..."
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
           -p 2222 root@localhost true 2>/dev/null; then
        echo "SSH ready after $((i * 5)) seconds"
        exit 0
    fi
    sleep 5
done
echo "SSH timeout after 10 minutes"
exit 1
```

**Speedup**: Enable KVM if on Linux host:

```yaml
# docker-compose.yml
devices:
  - /dev/kvm:/dev/kvm:rw
```

---

## SSH Authentication Failures

### Symptom

```bash
ssh -p 2222 root@localhost
# Password:  (enter "root")
# Permission denied, please try again.
```

**Causes**:
1. Wrong password
2. Root password not set
3. Password authentication disabled

---

### Solution 1: Reset Root Password

**Via serial console**:

```bash
# Connect to serial
telnet localhost 5555

# Login as root (may not need password if already logged in)
# Reset password
passwd
# Enter new password twice

# Test SSH
exit
ssh -p 2222 root@localhost
```

---

### Solution 2: Try Empty Password

Some Hurd images have empty root password by default:

```bash
# Just press Enter at password prompt
ssh -p 2222 root@localhost
# Password: (press Enter without typing anything)
```

---

### Solution 3: Check SSH Configuration

```bash
# Verify password auth enabled
docker-compose exec gnu-hurd-x86_64 \
    grep "PasswordAuthentication" /etc/ssh/sshd_config

# Should show:
PasswordAuthentication yes

# If not, enable:
docker-compose exec gnu-hurd-x86_64 \
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
docker-compose exec gnu-hurd-x86_64 systemctl restart ssh
```

---

### Solution 4: Use SSH Keys Instead

**More secure than passwords**:

```bash
# Generate SSH key on host
ssh-keygen -t ed25519 -f ~/.ssh/hurd_ed25519

# Copy public key to guest (via serial console)
telnet localhost 5555
# Login as root
mkdir -p /root/.ssh
chmod 700 /root/.ssh

# Paste public key content into:
cat > /root/.ssh/authorized_keys
# (paste content of ~/.ssh/hurd_ed25519.pub)
# Press Ctrl+D

chmod 600 /root/.ssh/authorized_keys
exit

# Test SSH with key
ssh -i ~/.ssh/hurd_ed25519 -p 2222 root@localhost
```

---

## Provisioning-Specific Issues

### SSH Installation Hangs (install-ssh-hurd.sh)

**Symptom**: `install-ssh-hurd.sh` script hangs waiting for login prompt

**Causes**:
1. System still booting (not ready)
2. Serial console not responding
3. Login prompt format unexpected

**Solutions**:

**1. Increase boot wait**:

```bash
# Wait longer before running script
sleep 900  # 15 minutes

# Then run
./scripts/install-ssh-hurd.sh
```

**2. Verify serial console manually**:

```bash
telnet localhost 5555
# Press Enter several times
# Check if login prompt appears
```

**3. Check expect script timeout**:

```bash
# Edit install-ssh-hurd.sh
# Increase timeout from 600 to 1200 seconds
sed -i 's/set timeout 600/set timeout 1200/' scripts/install-ssh-hurd.sh
```

---

### Package Installation Hangs During Provisioning

**Symptom**: `apt-get install openssh-server` hangs

**Causes**:
1. Network connectivity issues
2. Debian mirror slow
3. Entropy exhaustion

**Solutions**:

**1. Test network**:

```bash
# Inside guest
ping -c 3 8.8.8.8
ping -c 3 deb.debian.org
```

**2. Change mirror**:

```bash
# Use faster mirror
echo "deb http://ftp.us.debian.org/debian sid main" > /etc/apt/sources.list.d/us-mirror.list
apt-get update
```

**3. Install entropy daemon**:

```bash
# random-egd provides entropy for Hurd
apt-get install -y random-egd haveged
```

---

## SSH Commands Hang After Connection

### Symptom

```bash
ssh -p 2222 root@localhost
# Connected successfully
root@debian:~# ls
# (hangs, no output)
```

**Cause**: PTY (pseudo-terminal) allocation issues (Hurd-specific)

**Solutions**:

**1. Force PTY allocation**:

```bash
ssh -t -p 2222 root@localhost bash
```

**2. Disable PTY**:

```bash
ssh -T -p 2222 root@localhost uname -a
```

**3. Check shell**:

```bash
# Verify shell is /bin/bash
ssh -p 2222 root@localhost "echo \$SHELL"
```

---

## Reference Commands

### Quick SSH Test

```bash
# Test SSH connectivity (timeout after 5 seconds)
ssh -o ConnectTimeout=5 -p 2222 root@localhost true
```

### Check SSH Service Status

```bash
docker-compose exec gnu-hurd-x86_64 systemctl status ssh
```

### View SSH Logs

```bash
docker-compose exec gnu-hurd-x86_64 journalctl -u ssh -n 50
```

### Check Listening Ports

```bash
docker-compose exec gnu-hurd-x86_64 ss -tlnp
```

### Test SSH Config Syntax

```bash
docker-compose exec gnu-hurd-x86_64 sshd -t
```

### Restart SSH Service

```bash
docker-compose exec gnu-hurd-x86_64 systemctl restart ssh
```

---

## SSH Troubleshooting Checklist

Use this checklist to systematically diagnose SSH issues:

- [ ] **Container running**: `docker-compose ps` shows "Up"
- [ ] **Port accessible**: `nc -zv localhost 2222` succeeds
- [ ] **SSH installed**: `docker-compose exec gnu-hurd-x86_64 which sshd` returns path
- [ ] **SSH running**: `systemctl status ssh` shows "active (running)"
- [ ] **SSH listening**: `ss -tlnp | grep :22` shows LISTEN
- [ ] **Port mapping correct**: docker-compose.yml has `"2222:22"`
- [ ] **Password set**: Root password configured
- [ ] **Auth enabled**: sshd_config has `PasswordAuthentication yes`
- [ ] **Root login allowed**: sshd_config has `PermitRootLogin yes`
- [ ] **Firewall allows**: Host firewall permits port 2222
- [ ] **Network functional**: Guest can ping 8.8.8.8

If all checks pass but SSH still fails, see **COMMON-ISSUES.md** for general troubleshooting.

---

## Additional Resources

- **OpenSSH Manual**: https://www.openssh.com/manual.html
- **sshd_config Reference**: `man sshd_config` (inside guest)
- **GNU/Hurd SSH Guide**: https://www.gnu.org/software/hurd/hurd/translator/pflocal/ssh.html
- **Provisioning Guide**: `docs/05-CI-CD/PROVISIONED-IMAGE.md`

---

**Status**: Production Ready (x86_64-only)
**Last Updated**: 2025-11-07
**Architecture**: Pure x86_64
