# GNU/Hurd Docker - Port Forwarding Configuration

**Last Updated**: 2025-11-07
**Consolidated From**:
- PORT-MAPPING-GUIDE.md (2025-11-07)

**Purpose**: Complete guide to port forwarding architecture and configuration

**Scope**: Debian GNU/Hurd x86_64 only (i386 deprecated 2025-11-07)

---

## Overview

This document explains the **two-stage port forwarding** architecture used in the Docker-QEMU setup for GNU/Hurd x86_64.

**Two-Stage Model**:
1. **Docker Layer**: Host ports → Container ports (via docker-compose.yml)
2. **QEMU Layer**: Container ports → Guest ports (via user-mode NAT)

---

## Architecture Diagram

```
┌─────────────────────────────────────────────┐
│         Physical Host (CachyOS Linux)       │
│                                             │
│  User connects: ssh -p 2222 localhost      │
└─────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────┐
│           Docker Port Mapping               │
│   (host:2222 → container:2222)             │
└─────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────┐
│         Docker Container (Ubuntu 24.04)     │
│       (hurd-x86_64-qemu)                    │
│                                             │
│   QEMU receives on port 2222               │
└─────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────┐
│         QEMU User-Mode NAT                  │
│   (hostfwd=tcp::2222-:22)                   │
└─────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────┐
│      QEMU Guest (GNU/Hurd x86_64)          │
│      (debian-hurd-amd64)                    │
│                                             │
│   SSH daemon listening on port 22          │
│   Response: Data flows back through        │
│   same chain to user                       │
└─────────────────────────────────────────────┘
```

---

## Port Allocation Table (x86_64-only)

**Current Configuration** (single x86_64 service):

| Service | Host Port | Container Port | Guest Port | Protocol | Purpose |
|---------|-----------|----------------|------------|----------|---------|
| **SSH** | 2222 | 2222 | 22 | TCP | Remote terminal access |
| **HTTP** | 8080 | 8080 | 80 | TCP | Web server (if installed) |
| **Serial** | 5555 | 5555 | N/A | TCP | Serial console (telnet) |
| **Monitor** | 9999 | 9999 | N/A | TCP | QEMU HMP monitor (telnet) |
| **VNC** | 5900 | 5900 | N/A | TCP | Graphical console (optional) |
| **mosh** | 60000-60010 | 60000-60010 | 60000-60010 | UDP | Resilient SSH sessions |

**Notes**:
- Serial, Monitor, and VNC connect to QEMU, not guest OS
- mosh requires UDP port forwarding (10 concurrent sessions supported)
- All TCP services use standard two-stage forwarding

---

## SSH Access

### Basic SSH Connection

```bash
# Connect to GNU/Hurd x86_64 guest
ssh -p 2222 root@localhost

# Default credentials:
# Username: root
# Password: root OR empty (press Enter)
```

### SSH with Key-Based Authentication

**Recommended for security and automation**:

```bash
# Generate SSH key (on host)
ssh-keygen -t ed25519 -f ~/.ssh/hurd-dev -C "hurd-dev"

# Add to SSH config for convenience
cat >> ~/.ssh/config << 'EOF'
Host hurd-local
    HostName 127.0.0.1
    Port 2222
    User root
    IdentityFile ~/.ssh/hurd-dev
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF

# Connect easily
ssh hurd-local "uname -a"
```

**Inside Guest** (copy public key):
```bash
# Via serial console or initial SSH
mkdir -p /root/.ssh
chmod 700 /root/.ssh

# Copy public key from host (via 9p mount or paste)
cat /mnt/host/hurd-dev.pub >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
```

---

## HTTP Access

### Web Server Access

If HTTP server (e.g., Apache, nginx) is installed in guest:

```bash
# From host
curl http://localhost:8080

# Example: Install nginx inside guest
apt-get install nginx
systemctl start nginx

# Test from host
curl http://localhost:8080
# Expected: nginx welcome page
```

### Custom HTTP Port

To change HTTP port, update both layers:

**docker-compose.yml**:
```yaml
ports:
  - "8081:8080"  # Host:8081 → Container:8080
```

**entrypoint.sh** (QEMU args remain the same):
```bash
-netdev user,id=net0,hostfwd=tcp::8080-:80,...
# Container:8080 → Guest:80
```

---

## VNC Access (Graphical Console)

### Enable VNC

**Set ENABLE_VNC=1** in docker-compose.yml:

```yaml
environment:
  ENABLE_VNC: 1
```

**Connect from Host**:
```bash
# Using vncviewer
vncviewer localhost:5900

# Using TigerVNC
tigervnc localhost:5900

# Using RealVNC
xvnc4viewer localhost:5900
```

**VNC Port Mapping**:
```
Host:5900 → Container:5900 → QEMU VNC :0
```

**Note**: VNC connects directly to QEMU's VNC server, not a guest service.

**Display Resolution**:
- Default: 1024x768
- Change via QEMU args: `-vga std -device VGA,vgamem_mb=16`

---

## Serial Console Access

### Telnet to Serial Console

**Connect from Host**:
```bash
telnet localhost 5555

# Exit telnet: Ctrl+], then type "quit"
```

**Use Cases**:
- GRUB boot menu access
- Kernel boot messages
- Early boot debugging
- Emergency access if SSH fails

**Serial Console Port Mapping**:
```
Host:5555 → Container:5555 → QEMU serial port (ttyS0)
```

**Inside Guest** (check serial):
```bash
# Verify serial device
ls -l /dev/ttyS0

# Monitor serial console
tail -f /var/log/syslog
```

---

## QEMU Monitor Access (HMP)

### Telnet to QEMU Monitor

**Connect from Host**:
```bash
telnet localhost 9999

# QEMU monitor prompt appears:
QEMU 8.0.0 monitor - type 'help' for more information
(qemu)
```

**Common HMP Commands**:
```
(qemu) info status          # VM status
(qemu) info block           # Disk info
(qemu) info network         # Network info
(qemu) system_reset         # Hard reset
(qemu) system_powerdown     # ACPI shutdown
(qemu) savevm snapshot1     # Create snapshot
(qemu) loadvm snapshot1     # Restore snapshot
(qemu) sendkey f12          # Send keyboard key
(qemu) quit                 # Terminate QEMU (stops container)
```

**Monitor Port Mapping**:
```
Host:9999 → Container:9999 → QEMU HMP monitor
```

---

## mosh Access (Resilient SSH)

### UDP Port Forwarding for mosh

**Configure docker-compose.yml**:
```yaml
ports:
  - "2222:2222"                     # SSH
  - "60000-60010:60000-60010/udp"   # mosh (10 sessions)
```

**Configure entrypoint.sh** (QEMU args):
```bash
-netdev user,id=net0,\
hostfwd=tcp::2222-:22,\
hostfwd=udp::60000-:60000,\
hostfwd=udp::60001-:60001,\
...
hostfwd=udp::60010-:60010
```

**Install mosh in Guest**:
```bash
apt-get update
apt-get install -y mosh
```

**Connect from Host**:
```bash
# Basic mosh connection
mosh --ssh="ssh -p 2222" root@localhost

# With port range
mosh -p 60000:60010 --ssh="ssh hurd-local" localhost
```

**Benefits**:
- Persistent sessions across network changes
- Tolerates packet loss
- Instant keystroke response
- Automatic reconnection

---

## Detailed Port Mapping Breakdown

### Docker Layer (docker-compose.yml)

**Current Configuration**:
```yaml
services:
  hurd-x86_64:
    ports:
      - "2222:2222"   # SSH
      - "8080:8080"   # HTTP
      - "5555:5555"   # Serial console
      - "9999:9999"   # QEMU monitor
      - "5900:5900"   # VNC (if ENABLE_VNC=1)
      - "60000-60010:60000-60010/udp"  # mosh
```

**Format**: `"host_port:container_port"`

**Host Ports**:
- Published on 0.0.0.0 (all interfaces)
- Accessible from localhost
- Accessible from LAN (if firewall allows)
- Accessible from WAN (if port forwarding configured on router)

**Container Ports**:
- Internal to container network
- QEMU process binds to these ports
- Not directly accessible from host (requires Docker port mapping)

### QEMU Layer (entrypoint.sh)

**QEMU User-Mode NAT Configuration**:
```bash
-netdev user,id=net0,\
hostfwd=tcp::2222-:22,\
hostfwd=tcp::8080-:80,\
hostfwd=udp::60000-:60000,\
hostfwd=udp::60001-:60001,\
hostfwd=udp::60002-:60002,\
hostfwd=udp::60003-:60003,\
hostfwd=udp::60004-:60004,\
hostfwd=udp::60005-:60005,\
hostfwd=udp::60006-:60006,\
hostfwd=udp::60007-:60007,\
hostfwd=udp::60008-:60008,\
hostfwd=udp::60009-:60009,\
hostfwd=udp::60010-:60010
```

**Format**: `hostfwd=protocol::container_port-:guest_port`

**Guest Ports**:
- Services running inside Hurd guest
- SSH daemon on port 22
- HTTP server on port 80 (if installed)
- mosh on ports 60000-60010

### Complete Port Flow

**Example: SSH Connection**

```
┌─────────────────────────────────────────────┐
│ User:     ssh -p 2222 root@localhost       │
└─────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────┐
│ Host:     Port 2222                         │
│ Docker:   Forwards to container:2222       │
└─────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────┐
│ Container: Port 2222                        │
│ QEMU:      hostfwd=tcp::2222-:22            │
└─────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────┐
│ Guest:    SSH daemon on port 22            │
│ Response: Data flows back through chain    │
└─────────────────────────────────────────────┘
```

---

## Why This Design?

### Benefits of Two-Stage Forwarding

1. **Isolation**: Guest network isolated from host network
2. **Portability**: QEMU configs identical across environments
3. **Flexibility**: Easy to change host ports without modifying QEMU
4. **Security**: Guest cannot access host network directly
5. **Scalability**: Can run multiple containers without port conflicts

### QEMU User-Mode NAT Advantages

1. **No root required**: Unlike tap/bridge networking
2. **Automatic DHCP**: Guest gets IP automatically
3. **Automatic DNS**: Uses host's DNS resolver
4. **Simple configuration**: Just `hostfwd` rules
5. **Cross-platform**: Works on Linux, macOS, Windows

### Docker Port Mapping Advantages

1. **Expose specific ports**: Only published ports accessible
2. **Bind to specific interfaces**: Can limit to localhost
3. **Easy port changes**: Edit docker-compose.yml, no QEMU restart
4. **Multiple containers**: Each container gets unique host ports
5. **Health checks**: Docker can monitor port availability

---

## Common Issues and Solutions

### SSH Connection Refused

**Symptom**: `ssh -p 2222 localhost` → `Connection refused`

**Possible Causes**:
1. VM still booting (x86_64 can take 5-10 minutes)
2. SSH server not installed/started in guest
3. Docker port mapping incorrect
4. QEMU hostfwd not configured

**Diagnostic Steps**:
```bash
# 1. Check container is running
docker ps | grep hurd-x86_64-qemu

# 2. Check QEMU process inside container
docker exec hurd-x86_64-qemu ps aux | grep qemu-system-x86_64

# 3. Check QEMU has hostfwd configured
docker exec hurd-x86_64-qemu ps aux | grep "hostfwd=tcp::2222-:22"

# 4. Check Docker port mapping
docker port hurd-x86_64-qemu
# Expected: 2222/tcp -> 0.0.0.0:2222

# 5. Test from inside container
docker exec -it hurd-x86_64-qemu bash
telnet localhost 2222
# Should connect if QEMU forwarding works

# 6. Check guest SSH via serial console
telnet localhost 5555
# Inside guest:
systemctl status ssh
netstat -tlnp | grep :22
```

**Solutions**:
1. Wait longer for boot to complete
2. Start SSH manually in guest: `systemctl start ssh`
3. Verify docker-compose.yml has `ports: ["2222:2222"]`
4. Verify entrypoint.sh has `hostfwd=tcp::2222-:22`

### Port Already in Use

**Symptom**: Docker fails with `Bind for 0.0.0.0:2222 failed: port is already allocated`

**Cause**: Another process using port 2222

**Diagnostic**:
```bash
# Find process using port
ss -tlnp | grep 2222
# or
sudo lsof -i :2222

# Expected output if port in use:
# tcp   LISTEN  0  128  *:2222  *:*  users:(("process",pid=12345,...))
```

**Solutions**:

1. **Kill conflicting process**:
   ```bash
   sudo kill -9 12345  # Replace with actual PID
   ```

2. **Change host port** (recommended):
   ```yaml
   # docker-compose.yml
   ports:
     - "2223:2222"  # Use different host port

   # Connect with:
   ssh -p 2223 root@localhost
   ```

3. **Stop other containers**:
   ```bash
   docker ps | grep 2222
   docker stop <container_name>
   ```

### Serial Console Shows Nothing

**Symptom**: `telnet localhost 5555` connects but no output

**Causes**:
1. Hurd hasn't booted yet
2. GRUB menu passed (5-second auto-boot)
3. Kernel panic or boot failure

**Solutions**:

1. **Wait and press Enter**:
   ```bash
   # After connecting to serial console
   # Press Enter to wake console
   ```

2. **Check container logs**:
   ```bash
   docker logs hurd-x86_64-qemu | tail -50
   ```

3. **Use VNC instead** (if ENABLE_VNC=1):
   ```bash
   vncviewer localhost:5900
   ```

4. **Configure GRUB for serial console** (inside guest):
   ```bash
   # Edit /etc/default/grub
   GRUB_TERMINAL="serial console"
   GRUB_SERIAL_COMMAND="serial --unit=0 --speed=115200"

   # Update GRUB
   update-grub
   reboot
   ```

### VNC Connection Refused

**Symptom**: `vncviewer localhost:5900` fails

**Causes**:
1. ENABLE_VNC not set to 1
2. Docker port mapping missing
3. QEMU VNC not configured

**Solutions**:

1. **Enable VNC** in docker-compose.yml:
   ```yaml
   environment:
     ENABLE_VNC: 1

   ports:
     - "5900:5900"
   ```

2. **Restart container**:
   ```bash
   docker-compose up -d --force-recreate
   ```

3. **Verify VNC in QEMU** (check logs):
   ```bash
   docker logs hurd-x86_64-qemu | grep vnc
   # Expected: -vnc :0 (for port 5900)
   ```

### mosh Connection Hangs

**Symptom**: `mosh --ssh="ssh -p 2222" root@localhost` hangs

**Causes**:
1. mosh not installed in guest
2. UDP ports not exposed
3. QEMU UDP forwarding not configured

**Solutions**:

1. **Install mosh in guest**:
   ```bash
   ssh -p 2222 root@localhost
   apt-get update
   apt-get install -y mosh
   ```

2. **Expose UDP ports** in docker-compose.yml:
   ```yaml
   ports:
     - "60000-60010:60000-60010/udp"
   ```

3. **Add QEMU UDP forwarding** in entrypoint.sh:
   ```bash
   -netdev user,id=net0,\
   hostfwd=udp::60000-:60000,\
   hostfwd=udp::60001-:60001,\
   ...
   ```

4. **Test SSH first** (mosh requires SSH to work):
   ```bash
   ssh -p 2222 root@localhost "echo OK"
   ```

---

## Best Practices

### Port Management

1. **Keep QEMU ports consistent**: Always use `hostfwd=tcp::2222-:22`
2. **Document port allocations**: Maintain table of host ports used
3. **Use standard ports inside guest**: SSH on 22, HTTP on 80, etc.
4. **Avoid privileged ports on host**: Use ports > 1024 (e.g., 2222, not 22)

### Security

1. **Bind to localhost only** (if not needed on LAN):
   ```yaml
   ports:
     - "127.0.0.1:2222:2222"  # Only localhost can connect
   ```

2. **Use SSH keys instead of passwords**:
   - Generate keys: `ssh-keygen -t ed25519`
   - Disable password auth in guest

3. **Firewall host ports** (if exposed to network):
   ```bash
   # iptables example
   sudo iptables -A INPUT -p tcp --dport 2222 -s 192.168.1.0/24 -j ACCEPT
   sudo iptables -A INPUT -p tcp --dport 2222 -j DROP
   ```

4. **Change default ports** if exposing to internet:
   ```yaml
   ports:
     - "12345:2222"  # Non-standard host port
   ```

### Testing

1. **Test incrementally**: Get SSH working before adding other services
2. **Monitor QEMU logs**: Check `/var/log/qemu/guest-errors.log`
3. **Use telnet for quick tests**:
   ```bash
   telnet localhost 2222
   # Should see "SSH-2.0-OpenSSH_..." if SSH ready
   ```
4. **Check both layers**:
   - Docker: `docker port hurd-x86_64-qemu`
   - QEMU: `docker exec hurd-x86_64-qemu ps aux | grep hostfwd`

---

## Verification Checklist

```bash
# Check container running
docker ps | grep hurd-x86_64-qemu

# Verify port mappings
docker port hurd-x86_64-qemu

# Expected output:
# 2222/tcp -> 0.0.0.0:2222
# 5555/tcp -> 0.0.0.0:5555
# 8080/tcp -> 0.0.0.0:8080
# 9999/tcp -> 0.0.0.0:9999
# 60000-60010/udp -> 0.0.0.0:60000-60010

# Test SSH (after boot completes)
ssh -p 2222 root@localhost "uname -a"
# Expected: GNU hurd ... x86_64 ...

# Test serial console
echo "" | telnet localhost 5555
# Should connect

# Test QEMU monitor
echo "info status" | telnet localhost 9999
# Should show VM status

# Check host ports listening
ss -tlnp | grep -E '(2222|5555|8080|9999|5900)'

# All ports should show LISTEN state
```

---

## Advanced Configuration

### Multiple Port Ranges

**Expose range of ports for services**:

```yaml
# docker-compose.yml
ports:
  - "3000-3010:3000-3010"  # Range for web services
```

**QEMU forwarding** (entrypoint.sh):
```bash
# Loop to create multiple hostfwd rules
for i in {3000..3010}; do
  HOSTFWD_OPTS+=",hostfwd=tcp::$i-:$i"
done
```

### Custom Network Interface

**Bind to specific interface**:

```yaml
# docker-compose.yml
ports:
  - "192.168.1.100:2222:2222"  # Only on specific IP
```

### IPv6 Support

**Enable IPv6** (experimental):

```yaml
# docker-compose.yml
networks:
  hurd-net:
    enable_ipv6: true
    ipam:
      config:
        - subnet: "2001:db8::/64"
```

**QEMU IPv6** (not currently supported in user-mode NAT):
- Use tap/bridge networking for IPv6
- Requires more complex setup

---

## Troubleshooting Commands Reference

```bash
# Docker Layer Diagnostics
docker ps                            # Check container running
docker port <container>              # Show port mappings
docker logs <container>              # View container logs
docker exec <container> bash         # Enter container shell

# QEMU Layer Diagnostics
docker exec <container> ps aux | grep qemu   # Check QEMU process
docker exec <container> netstat -tlnp        # Check container ports

# Host Layer Diagnostics
ss -tlnp | grep <port>               # Check host port listening
sudo lsof -i :<port>                 # Find process using port
iptables -L -n -v                    # Check firewall rules

# Guest Layer Diagnostics (via serial or SSH)
systemctl status ssh                 # Check SSH service
netstat -tlnp                        # Check guest services
ip addr show                         # Check guest IP
ping 10.0.2.2                        # Test connectivity to QEMU gateway
```

---

## Summary

**Port Forwarding Architecture**:
- **Two-stage model**: Host → Docker → QEMU → Guest
- **Docker Layer**: Publishes container ports to host
- **QEMU Layer**: Forwards container ports to guest

**Default Ports**:
- SSH: 2222 → 2222 → 22
- HTTP: 8080 → 8080 → 80
- Serial: 5555 (QEMU serial console)
- Monitor: 9999 (QEMU HMP monitor)
- VNC: 5900 (QEMU VNC server, optional)
- mosh: 60000-60010/UDP (resilient SSH)

**Best Practices**:
- Keep QEMU ports consistent
- Use SSH keys, not passwords
- Test incrementally
- Document port allocations
- Monitor logs for errors

---

**Status**: Production Ready (x86_64-only)
**Last Updated**: 2025-11-07
**Maintainer**: Oichkatzelesfrettschen
**Architecture**: Pure x86_64
