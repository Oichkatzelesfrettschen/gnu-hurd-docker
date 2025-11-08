# GNU/Hurd Docker - Credentials and Access Reference

**Last Updated**: 2025-11-07
**Consolidated From**:
- docs/CREDENTIALS.md (original credentials documentation)

**Purpose**: Complete reference for default credentials, access methods, and security

**Scope**: Debian GNU/Hurd x86_64 only (i386 deprecated 2025-11-07)

---

## Overview

This document covers all access credentials and authentication methods for the Debian GNU/Hurd x86_64 Docker environment, including default passwords, SSH configuration, serial console access, and security recommendations.

**Key Access Methods**:
1. **SSH** - Primary access method (host port 2222 → guest port 22)
2. **Serial Console** - Emergency access via telnet (host port 5555)
3. **Docker Exec** - Direct container shell access (no QEMU guest access)

**Default Credentials**:
- **Root**: `root` / `root` (password auth enabled after provisioning)
- **Agents**: `agents` / `agents` (sudo NOPASSWD enabled)

**Security Level**: **Development Only** - Change passwords for production

---

## Table of Contents

1. [Default User Accounts](#default-user-accounts)
2. [SSH Access](#ssh-access)
3. [Serial Console Access](#serial-console-access)
4. [Creating User Accounts](#creating-user-accounts)
5. [Security Recommendations](#security-recommendations)
6. [SSH Key-Based Authentication](#ssh-key-based-authentication)
7. [Port Mappings](#port-mappings)
8. [Network Configuration](#network-configuration)
9. [Volume Mounts](#volume-mounts)
10. [Troubleshooting Access Issues](#troubleshooting-access-issues)

---

## Default User Accounts

### Root Account

The Debian GNU/Hurd x86_64 system includes a root account for administrative tasks.

**Username**: `root`
**Password** (after provisioning): `root`
**Default Shell**: `/bin/bash`
**Home Directory**: `/root`
**UID**: `0` (superuser)

**Official Image Defaults** (before provisioning):
- **Login Method**: SSH with key-based authentication preferred
- **Password Auth**: May be disabled by default (`PermitRootLogin prohibit-password`)
- **Empty Password**: Some images allow empty password (press Enter only)

**After Provisioning** (via `install-ssh-hurd.sh` or `bringup-and-provision.sh`):
- **Password**: Set to `root`
- **Password Auth**: Enabled (`PermitRootLogin yes`)
- **SSH Service**: Running and accessible on port 2222

**Root User Capabilities**:
- Full system access (UID 0)
- Install packages (`apt-get install`)
- Modify system configuration
- Create users (`useradd`, `adduser`)
- Manage services (`systemctl`)

---

### Agents Account

The `agents` user is created during provisioning for non-root administrative tasks.

**Username**: `agents`
**Password**: `agents`
**Default Shell**: `/bin/bash`
**Home Directory**: `/home/agents`
**Groups**: `sudo` (passwordless sudo enabled)
**UID**: Typically `1000` (first non-system user)

**Sudo Configuration**:
- **File**: `/etc/sudoers.d/agents`
- **Content**: `agents ALL=(ALL) NOPASSWD:ALL`
- **Effect**: `agents` can run any command as root without password

**Agents User Capabilities**:
- Run sudo commands without password (`sudo apt-get install`)
- Switch to root (`sudo -i` or `su -`)
- Full administrative access (via sudo)
- Ideal for development workflows (no password prompts)

**Why "agents"?**:
- Named after typical CI/CD agent users
- Convenient for automated testing and builds
- Separates development work from root account

---

## SSH Access

SSH is the primary access method for the GNU/Hurd guest system.

### Port Mapping

**Host**: `localhost:2222`
**Guest**: `10.0.2.15:22` (QEMU user networking internal IP)

**Connection**:
```bash
# Connect as root
ssh -p 2222 root@localhost
# Password: root

# Connect as agents
ssh -p 2222 agents@localhost
# Password: agents
```

### Default Behavior (Before Provisioning)

**Official Debian Hurd Image**:
- SSH server may not be installed
- If installed, password authentication may be disabled
- Root login may be restricted (`PermitRootLogin prohibit-password`)

**Symptom**: SSH connection refused or password rejected

**Solution**: Run provisioning scripts

```bash
# Method 1: Automated provisioning (via serial console)
./scripts/install-ssh-hurd.sh

# Method 2: Manual installation (via serial console)
# Connect to serial console (telnet localhost:5555)
# login: root
# Password: [empty or default]
apt-get update
apt-get install -y openssh-server random-egd
echo 'root:root' | chpasswd
sed -i 's/.*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/.*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
systemctl restart ssh
```

### After Provisioning

**SSH Configuration** (`/etc/ssh/sshd_config`):
```bash
PermitRootLogin yes                    # Allow root login
PasswordAuthentication yes             # Allow password authentication
PubkeyAuthentication yes               # Allow SSH key authentication
PermitEmptyPasswords no                # Require password (security)
ChallengeResponseAuthentication no     # Disable challenge-response
UsePAM yes                             # Use PAM for authentication
```

**SSH Service Status**:
```bash
# Check SSH service (inside guest)
systemctl status ssh

# Restart SSH (if configuration changed)
systemctl restart ssh
```

### SSH Connection Examples

**Basic connection**:
```bash
# Root user
ssh -p 2222 root@localhost

# Agents user
ssh -p 2222 agents@localhost
```

**Execute single command**:
```bash
# Run uname as root
ssh -p 2222 root@localhost uname -a

# Run apt-get update as agents (with sudo)
ssh -p 2222 agents@localhost sudo apt-get update
```

**Copy files via SCP**:
```bash
# Copy file from host to guest
scp -P 2222 local-file.txt root@localhost:/root/

# Copy file from guest to host
scp -P 2222 root@localhost:/etc/fstab ./fstab-backup.txt
```

**Port forwarding** (expose guest service to host):
```bash
# Forward guest port 8080 to host port 9090
ssh -p 2222 -L 9090:localhost:8080 root@localhost

# Access guest service from host
curl http://localhost:9090
```

---

## Serial Console Access

The serial console provides direct TTY access for troubleshooting when SSH is unavailable.

### Port Mapping

**Host**: `localhost:5555` (telnet)
**Guest**: `/dev/ttyS0` (serial port)

**Connection**:
```bash
# Method 1: telnet
telnet localhost 5555

# Method 2: connect-console.sh script
./scripts/connect-console.sh
```

### Exit Serial Console

**telnet**:
- Press `Ctrl+]` to enter telnet command mode
- Type `quit` and press Enter

**screen** (if using screen instead):
- Press `Ctrl+A` followed by `k` (kill)
- Confirm with `y`

### Serial Console Login

**Before Provisioning**:
- **Login**: `root`
- **Password**: Empty (press Enter only) OR check Debian release notes

**After Provisioning**:
- **Login**: `root`
- **Password**: `root`

### Serial Console Use Cases

1. **Boot troubleshooting**: Watch boot messages, diagnose kernel panics
2. **SSH unavailable**: Access system when SSH service is down
3. **Network issues**: Configure network when SSH unreachable
4. **Emergency access**: Reset root password, repair filesystem
5. **Automation**: Use `expect` scripts for automated configuration

### Example: Reset Root Password via Serial Console

```bash
# Connect to serial console
telnet localhost 5555

# Press Enter to wake up console
# [Press Enter]

# Login as root (empty password or 'root')
login: root
Password: [Enter]

# Reset root password
root@hurd:~# passwd root
Enter new password: newpassword
Retype new password: newpassword
passwd: password updated successfully

# Exit serial console
root@hurd:~# [Ctrl+] then type 'quit'
```

---

## Creating User Accounts

### Method 1: Automated (configure-users.sh)

**Script**: `scripts/configure-users.sh`

**What it creates**:
- Root account with password `root`
- Agents account with password `agents`
- Agents user with `NOPASSWD` sudo
- SSH directories (`~/.ssh/`)
- Proper file permissions

**Usage**:
```bash
# Inside guest (as root)
./scripts/configure-users.sh
```

**Result**:
- `/etc/sudoers.d/agents` created with `NOPASSWD` config
- `/root/.ssh/` and `/home/agents/.ssh/` created
- Passwords set for both accounts

---

### Method 2: Manual User Creation

**Create standard user**:
```bash
# Inside guest (as root)
useradd -m -s /bin/bash newuser

# Set password
passwd newuser
# Enter password twice
```

**Add to sudo group**:
```bash
# Add user to sudo group
usermod -aG sudo newuser

# Verify groups
groups newuser
# Output: newuser : newuser sudo
```

**Configure passwordless sudo** (optional):
```bash
# Create sudoers drop-in file
echo 'newuser ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/newuser
chmod 0440 /etc/sudoers.d/newuser

# Verify syntax
visudo -c
# Output: /etc/sudoers.d/newuser: parsed OK
```

**Setup SSH directory**:
```bash
# As newuser
mkdir -p ~/.ssh
chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

---

## Security Recommendations

### For Development/Testing

**Acceptable Practices**:
1. Use default passwords (`root` / `agents`) for local development
2. Expose SSH on localhost only (`127.0.0.1:2222`)
3. Use Docker host firewall for network isolation

**Recommended Practices**:
1. **Change default passwords** after initial setup:
   ```bash
   passwd root
   passwd agents
   ```

2. **Create standard user account** for daily use:
   ```bash
   useradd -m -G sudo devuser
   passwd devuser
   ```

3. **Disable root SSH** (optional, for enhanced security):
   ```bash
   # Edit /etc/ssh/sshd_config
   PermitRootLogin no

   # Restart SSH
   systemctl restart ssh
   ```

---

### For Production

**CRITICAL: Production deployments must NOT use default credentials**

**Required Security Measures**:
1. **Change all default passwords** before exposing to network
   ```bash
   passwd root
   passwd agents
   # Use strong passwords (16+ chars, mixed case, symbols)
   ```

2. **Use SSH key-based authentication** instead of passwords
   ```bash
   # Disable password authentication
   sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
   systemctl restart ssh
   ```

3. **Create standard user accounts** for all administrative tasks
   ```bash
   # Never use root directly in production
   useradd -m -s /bin/bash adminuser
   passwd adminuser
   usermod -aG sudo adminuser
   ```

4. **Restrict SSH access** to specific hosts/networks
   ```bash
   # Edit /etc/ssh/sshd_config
   AllowUsers adminuser@192.168.1.0/24
   DenyUsers root
   ```

5. **Enable firewall rules** on Docker host
   ```bash
   # Only allow SSH from specific IP
   iptables -A INPUT -p tcp --dport 2222 -s 192.168.1.100 -j ACCEPT
   iptables -A INPUT -p tcp --dport 2222 -j DROP
   ```

6. **Use secrets management** for sensitive credentials
   - Use environment variables for passwords
   - Store SSH keys in encrypted vault
   - Rotate credentials regularly (90-day cycle)

7. **Run regular security updates**
   ```bash
   apt-get update
   apt-get dist-upgrade
   ```

8. **Monitor access logs**
   ```bash
   # Check SSH authentication attempts
   journalctl -u ssh -f

   # Check failed login attempts
   grep "Failed password" /var/log/auth.log
   ```

---

## SSH Key-Based Authentication

SSH keys provide secure authentication without passwords.

### Generate SSH Key (On Host)

**One-time setup**:
```bash
# Generate ed25519 key (recommended, modern)
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_hurd -C "hurd-dev"

# Or generate RSA key (compatible, older)
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa_hurd -C "hurd-dev"

# Accept default location or specify custom path
# Enter passphrase (recommended for security)
```

**Output**:
- Private key: `~/.ssh/id_ed25519_hurd` (keep secret!)
- Public key: `~/.ssh/id_ed25519_hurd.pub` (copy to guest)

---

### Copy Public Key to Guest

**Method 1: ssh-copy-id (automatic)**:
```bash
# Copy public key to guest
ssh-copy-id -i ~/.ssh/id_ed25519_hurd.pub -p 2222 root@localhost

# Enter password when prompted: root

# Test key-based login
ssh -i ~/.ssh/id_ed25519_hurd -p 2222 root@localhost
# Should login without password
```

**Method 2: Manual copy**:
```bash
# Display public key
cat ~/.ssh/id_ed25519_hurd.pub

# Copy output to clipboard

# SSH to guest
ssh -p 2222 root@localhost

# Inside guest, append public key
mkdir -p ~/.ssh
chmod 700 ~/.ssh
echo "ssh-ed25519 AAAAC3... your-comment" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

---

### SSH Config (Convenience)

**Create SSH config** (`~/.ssh/config` on host):
```bash
Host hurd-dev
    HostName localhost
    Port 2222
    User root
    IdentityFile ~/.ssh/id_ed25519_hurd
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host hurd-agents
    HostName localhost
    Port 2222
    User agents
    IdentityFile ~/.ssh/id_ed25519_hurd
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
```

**Usage**:
```bash
# Connect to root (no password needed)
ssh hurd-dev

# Connect to agents
ssh hurd-agents

# Copy files
scp file.txt hurd-dev:/root/
```

---

### Disable Password Authentication (After Key Setup)

**Once SSH keys are configured and tested**:
```bash
# Inside guest, edit SSH config
sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config

# Verify change
grep PasswordAuthentication /etc/ssh/sshd_config
# Output: PasswordAuthentication no

# Restart SSH
systemctl restart ssh
```

**Test**:
```bash
# Key-based login should work
ssh -i ~/.ssh/id_ed25519_hurd -p 2222 root@localhost
# Success!

# Password login should fail
ssh -p 2222 root@localhost
# Permission denied (publickey)
```

---

## Port Mappings

Current port mappings from Docker host to Hurd guest:

| Host Port | Guest Port | Service | Usage |
|-----------|------------|---------|-------|
| **2222** | **22** | SSH | Primary access (terminal, SCP, SFTP) |
| **5555** | `/dev/ttyS0` | Serial Console | Emergency access, boot debugging |
| **9999** | **9999** | Custom | Extensible for additional services |

### Add Custom Port Mappings

**Edit docker-compose.yml**:
```yaml
services:
  hurd-x86_64:
    ports:
      - "2222:22"       # SSH (existing)
      - "5555:5555"     # Serial console (existing)
      - "8080:80"       # HTTP service (new)
      - "3000:3000"     # Node.js app (new)
      - "5432:5432"     # PostgreSQL (new)
```

**Apply changes**:
```bash
# Rebuild and restart container
docker-compose down
docker-compose up -d --force-recreate
```

**Verify port forwarding**:
```bash
# Check port mappings
docker-compose ps
# Output:
# NAME            PORTS
# hurd-x86_64     0.0.0.0:2222->22/tcp, 0.0.0.0:8080->80/tcp, ...

# Test port forwarding
curl http://localhost:8080
```

---

## Network Configuration

### QEMU User Networking (Default)

**Network Type**: NAT (Network Address Translation)
**Guest IP**: Assigned by QEMU user networking (typically `10.0.2.15`)
**Gateway**: `10.0.2.2` (QEMU user network gateway)
**DNS**: Uses host's DNS resolver (automatic)
**DHCP**: Automatic IP assignment via QEMU

**Advantages**:
- No host configuration needed
- Automatic DNS resolution
- Outbound connectivity works immediately
- Isolated guest network (security)

**Limitations**:
- Guest not directly accessible from external network
- Port forwarding required for inbound connections
- Slightly higher latency than bridged networking

---

### Check Network Configuration (Inside Guest)

**View network interfaces**:
```bash
# Show all interfaces
ifconfig

# Or use ip command
ip addr show
```

**Expected output**:
```
eth0: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500
        inet 10.0.2.15  netmask 255.255.255.0  broadcast 10.0.2.255
        ether 52:54:00:12:34:56  txqueuelen 1000  (Ethernet)
```

**Test connectivity**:
```bash
# Test external network
ping -c 3 8.8.8.8
# 3 packets transmitted, 3 received, 0% packet loss

# Test DNS resolution
ping -c 3 google.com
# 3 packets transmitted, 3 received, 0% packet loss

# Check routing table
netstat -rn
# Or: ip route show
```

**Expected routing table**:
```
Kernel IP routing table
Destination     Gateway         Genmask         Flags   MSS Window  irtt Iface
0.0.0.0         10.0.2.2        0.0.0.0         UG        0 0          0 eth0
10.0.2.0        0.0.0.0         255.255.255.0   U         0 0          0 eth0
```

---

### Configure Static IP (Advanced)

**Default DHCP is recommended**. For static IP configuration:

**Edit /etc/network/interfaces**:
```bash
# Static IP configuration
auto eth0
iface eth0 inet static
    address 10.0.2.15
    netmask 255.255.255.0
    gateway 10.0.2.2
    dns-nameservers 8.8.8.8 1.1.1.1
```

**Apply configuration**:
```bash
# Restart networking
systemctl restart networking

# Or bring interface down/up
ifdown eth0 && ifup eth0
```

---

## Volume Mounts

### Default Mounts

**QCOW2 Image**:
- **Host Path**: `./debian-hurd-amd64-80gb.qcow2` (project root)
- **Guest Access**: Entire QCOW2 disk mounted as root filesystem
- **Persistence**: All changes persist in QCOW2 file

**Docker Bind Mounts** (optional, configure in docker-compose.yml):
```yaml
volumes:
  - ./share:/mnt/share:ro   # Read-only shared directory
  - ./scripts:/root/scripts:rw  # Scripts directory
```

---

### Share Files Between Host and Guest

**Method 1: SCP (Recommended)**:
```bash
# Copy file from host to guest
scp -P 2222 local-file.txt root@localhost:/root/

# Copy directory from host to guest
scp -P 2222 -r local-dir/ root@localhost:/root/

# Copy from guest to host
scp -P 2222 root@localhost:/etc/fstab ./fstab-backup.txt
```

**Method 2: Docker Bind Mount**:
```yaml
# docker-compose.yml
volumes:
  - ./share:/mnt/share:rw
```

**Inside guest**:
```bash
# Files in /mnt/share/ are accessible from both host and guest
ls /mnt/share/
```

**Method 3: Serial Console Paste** (Small text files):
```bash
# Connect to serial console
telnet localhost 5555

# Login as root
login: root
Password: root

# Create file with heredoc
cat > /root/file.txt << 'EOF'
[paste content here]
EOF
```

---

## Troubleshooting Access Issues

### SSH Connection Refused

**Symptom**: `ssh: connect to host localhost port 2222: Connection refused`

**Diagnosis**:
```bash
# Check if container is running
docker-compose ps
# Container should be "Up"

# Check if SSH service is running inside guest
docker-compose exec hurd-x86_64 ps aux | grep sshd
# Should show /usr/sbin/sshd

# Check port mapping
docker-compose ps
# Should show 0.0.0.0:2222->22/tcp
```

**Solutions**:
1. **Container not running**: `docker-compose up -d`
2. **SSH not installed**: Use serial console to install:
   ```bash
   telnet localhost 5555
   # login: root
   apt-get update
   apt-get install -y openssh-server random-egd
   systemctl start ssh
   ```
3. **Port conflict**: Change host port in docker-compose.yml

---

### SSH Password Rejected

**Symptom**: `Permission denied (publickey,password)`

**Diagnosis**:
```bash
# Check SSH configuration inside guest
ssh -p 2222 root@localhost cat /etc/ssh/sshd_config | grep -E "PermitRootLogin|PasswordAuthentication"
```

**Expected**:
```
PermitRootLogin yes
PasswordAuthentication yes
```

**Solutions**:
1. **Password auth disabled**: Enable via serial console:
   ```bash
   sed -i 's/.*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
   systemctl restart ssh
   ```
2. **Root login disabled**: Enable via serial console:
   ```bash
   sed -i 's/.*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
   systemctl restart ssh
   ```
3. **Wrong password**: Try empty password (press Enter only)

---

### Serial Console Unresponsive

**Symptom**: `telnet localhost 5555` connects but no login prompt

**Diagnosis**:
```bash
# Check if QEMU is running
docker-compose logs | grep qemu-system-x86_64

# Check serial port configuration
docker-compose logs | grep "char device redirected"
```

**Solutions**:
1. **Console sleeping**: Press Enter several times to wake up
2. **Boot not complete**: Wait 2-5 minutes for full boot
3. **QEMU crashed**: Check logs, restart container:
   ```bash
   docker-compose logs | tail -50
   docker-compose restart
   ```

---

### Password Not Working

**Symptom**: Login prompt accepts username but rejects password

**Solutions**:
1. **Try empty password**: Press Enter only (no password)
2. **Try default password**: `root` for root user, `agents` for agents
3. **Reset via serial console**:
   ```bash
   # Login with empty password
   login: root
   Password: [press Enter]

   # Set new password
   passwd root
   ```

---

### QEMU Not Started

**Symptom**: Container runs but QEMU doesn't start

**Diagnosis**:
```bash
# Check container logs
docker-compose logs

# Verify QCOW2 image exists
ls -lh debian-hurd-amd64-80gb.qcow2

# Check image integrity
qemu-img check debian-hurd-amd64-80gb.qcow2
```

**Solutions**:
1. **Missing QCOW2 image**: Run `./scripts/setup-hurd-amd64.sh`
2. **Corrupted image**: Restore from backup or re-download
3. **Entrypoint error**: Check Docker logs for shell errors
4. **Rebuild container**:
   ```bash
   docker-compose down
   docker-compose build --no-cache
   docker-compose up -d
   ```

---

### Network Connectivity Issues (Inside Guest)

**Symptom**: `ping 8.8.8.8` fails inside guest

**Diagnosis**:
```bash
# Check interface status
ip addr show eth0

# Check routing table
ip route show

# Check DNS configuration
cat /etc/resolv.conf
```

**Solutions**:
1. **Interface down**: Bring up interface:
   ```bash
   dhclient eth0
   # Or: ifup eth0
   ```
2. **No DNS**: Add fallback DNS:
   ```bash
   echo "nameserver 8.8.8.8" >> /etc/resolv.conf
   ```
3. **QEMU networking broken**: Restart container:
   ```bash
   docker-compose restart
   ```

---

## Environment Variables

The Docker container inherits no special environment variables beyond standard Linux.

### Set Persistent Environment Variables

**System-wide** (all users):
```bash
# Edit /etc/environment
echo "VARIABLE=value" >> /etc/environment

# Reload (requires login)
source /etc/environment
```

**User-specific** (root or agents):
```bash
# Edit ~/.bashrc
echo "export VARIABLE=value" >> ~/.bashrc

# Reload
source ~/.bashrc
```

**Session-only** (temporary):
```bash
# Set for current session
export VARIABLE=value

# Verify
echo $VARIABLE
```

---

## References

- **Debian GNU/Hurd**: https://www.debian.org/ports/hurd/
- **QEMU Documentation**: https://www.qemu.org/documentation/
- **SSH Guide**: https://www.digitalocean.com/community/tutorials/how-to-configure-ssh-key-based-authentication-on-a-linux-server
- **QEMU Networking**: https://wiki.qemu.org/Documentation/Networking

---

## Security Notes

**Critical Reminders**:
- **Do not** share default root password publicly
- **Do not** use default passwords in production
- **Always** use SSH keys for remote access
- **Always** create standard user accounts for regular tasks
- **Always** run security updates (`apt-get dist-upgrade`)
- **Always** change default passwords immediately for production

**Development vs Production**:
- **Development**: Default passwords acceptable for localhost-only access
- **Production**: Change all passwords, use SSH keys, restrict access

---

**Status**: Production Ready (x86_64-only)
**Last Updated**: 2025-11-07
**Architecture**: Pure x86_64
