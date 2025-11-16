# Troubleshooting Guide

## Docker and Docker Compose Issues

### Docker Daemon Won't Start

**Error:** `daemon is not responding` or `Cannot connect to Docker daemon`

**Solutions:**
```bash
# Check if Docker service is running
sudo systemctl status docker

# Start Docker service
sudo systemctl start docker

# Enable on boot
sudo systemctl enable docker

# Check Docker logs
sudo journalctl -u docker -n 100

# Verify Docker can run
docker ps

# If permission denied, add user to group
sudo usermod -aG docker $USER
newgrp docker
```

### Permission Denied Errors

**Error:** `permission denied while trying to connect to Docker daemon socket`

**Solutions:**
```bash
# Add user to docker group
sudo usermod -aG docker $USER

# Apply group changes
newgrp docker

# Verify Docker socket permissions
ls -la /var/run/docker.sock
# Should show: srw-rw---- 1 root docker

# Log out and back in
exit
# Then login again and verify
docker ps
```

### Image Build Fails

**Error:** `docker-compose build` fails with errors

**Solutions:**
```bash
# Check available disk space (need 8GB+)
df -h /

# Clear Docker cache
docker-compose build --no-cache

# Check Dockerfile syntax
docker build --dry-run .

# View detailed build output
docker-compose build --progress=plain

# Check network connectivity
ping 8.8.8.8
ping deb.debian.org  # For package downloads
```

### Port Conflicts

**Error:** `Ports are not available; port 2222 is already allocated`

**Solutions:**
```bash
# Check what's using port 2222
lsof -i :2222
# or
netstat -tulpn | grep 2222

# Stop conflicting service
sudo systemctl stop <service>

# Use different port in docker-compose.yml
# Change: "2222:2222" to "2223:2222"
docker-compose up -d
```

## Container Issues

### Container Won't Start

**Error:** `docker-compose up -d` fails

**Solutions:**
```bash
# Check container logs
docker-compose logs --tail=100

# Verify QCOW2 image exists
ls -lh debian-hurd-i386-20251105.qcow2

# Check volume mount paths
grep -A 3 "volumes:" docker-compose.yml

# Try running with interactive output to see errors
docker-compose up
# Press Ctrl+C to stop

# Check container status
docker ps -a | grep gnu-hurd

# Remove failed container and retry
docker-compose down -v
docker-compose up -d
```

### Container Exits Immediately

**Error:** `docker-compose ps` shows `Exited (1)`

**Solutions:**
```bash
# View exit logs
docker-compose logs --tail=50

# Check entrypoint.sh for syntax errors
shellcheck entrypoint.sh

# Verify image built successfully
docker image ls | grep gnu-hurd

# Try rebuilding image
docker-compose build --no-cache
docker-compose up -d
```

### Container Consumes Too Much Memory

**Error:** Container using more than allocated memory

**Solutions:**
```bash
# Check current usage
docker stats gnu-hurd-dev

# Reduce QEMU memory allocation in entrypoint.sh
# Change: -m 1.5G to -m 1G
docker-compose build --no-cache
docker-compose up -d

# Check QEMU process inside container
docker-compose exec gnu-hurd-dev ps aux | grep qemu

# Reduce system packages
docker-compose exec gnu-hurd-dev apt-get autoremove
```

## QEMU and GNU/Hurd Issues

### QEMU Hangs During Boot

**Symptom:** QEMU starts but system doesn't boot past GRUB

**Solutions:**
```bash
# This is normal - GRUB may wait for input
# At serial console, press Enter:
screen /dev/pts/X
# Press: Enter

# If still hung after 5 minutes:
# Check boot logs
docker-compose logs | tail -100

# Increase QEMU timeout in entrypoint.sh
# Note: timeout is typically 5-10 minutes normal boot time

# Try with verbose QEMU output
# Edit entrypoint.sh to add: -d guest_errors,cpu_reset
docker-compose build
docker-compose up -d

# Monitor QEMU debug log
tail -f /tmp/qemu.log  # Inside container or via docker-compose exec
```

### Serial Console Not Responding

**Error:** Serial console appears but no input accepted

**Solutions:**
```bash
# Find correct PTY
docker-compose logs | grep "char device redirected"

# Try pressing Enter to wake console
screen /dev/pts/X
# Press: Enter, Enter, Enter

# Check TTY settings
stty -a

# If corrupted, kill and restart
# Ctrl+A then :quit to exit screen
# Try new connection
screen /dev/pts/X

# Debug QEMU serial configuration
docker-compose exec gnu-hurd-dev ps aux | grep serial
```

### SSH Not Working

**Error:** `ssh -p 2222 root@localhost` connection refused

**Solutions:**
```bash
# Verify SSH service is running inside container
docker-compose exec gnu-hurd-dev systemctl status ssh

# Start SSH if stopped
docker-compose exec gnu-hurd-dev systemctl start ssh

# Check port mapping
docker-compose ps
# Should show: 0.0.0.0:2222->22/tcp

# Test port is open on host
nc -zv localhost 2222

# Verify SSH listening on correct port inside container
docker-compose exec gnu-hurd-dev netstat -tulpn | grep ":22"

# Check SSH configuration
docker-compose exec gnu-hurd-dev cat /etc/ssh/sshd_config | grep -E "Port|Listen"

# Restart SSH with verbose output
docker-compose exec gnu-hurd-dev systemctl restart ssh
docker-compose logs --tail=10
```

### Network Connectivity Issues

**Error:** Cannot ping external hosts or resolve DNS

**Solutions:**
```bash
# Test connectivity inside container
docker-compose exec gnu-hurd-dev ping 8.8.8.8

# Check routing
docker-compose exec gnu-hurd-dev netstat -rn
# Should show default gateway at 10.0.2.2

# Check DNS resolution
docker-compose exec gnu-hurd-dev cat /etc/resolv.conf

# Manually set DNS if needed
docker-compose exec gnu-hurd-dev bash
# Inside: echo "nameserver 8.8.8.8" > /etc/resolv.conf

# Check network interfaces
docker-compose exec gnu-hurd-dev ip addr show
docker-compose exec gnu-hurd-dev ip route show
```

### System Boots But Can't Login

**Error:** GRUB boots successfully but login fails

**Solutions:**
```bash
# Try empty password (just press Enter)
screen /dev/pts/X
# At login prompt: root
# At password: (just press Enter)

# If password protected, check CREDENTIALS.md
# Default might be documented or require reset

# Boot into recovery/single-user mode (if GRUB supports)
# At GRUB menu, select recovery kernel option
# Or manually boot with init=/bin/bash

# From host, reset root password
docker-compose exec gnu-hurd-dev passwd root
# Enter new password twice

# Check /etc/passwd file
docker-compose exec gnu-hurd-dev cat /etc/passwd | head -5
```

## Disk and Storage Issues

### Disk Image Corrupted

**Error:** QEMU refuses to boot from QCOW2

**Solutions:**
```bash
# Check QCOW2 integrity
qemu-img check debian-hurd-i386-20251105.qcow2

# Repair if needed
qemu-img check -r all debian-hurd-i386-20251105.qcow2

# Create backup
cp debian-hurd-i386-20251105.qcow2 debian-hurd-i386-20251105.qcow2.backup

# Convert back to raw and reconvert
qemu-img convert -f qcow2 debian-hurd-i386-20251105.qcow2 temp.img
qemu-img convert -f raw -O qcow2 temp.img debian-hurd-i386-20251105.qcow2
rm temp.img

# Or redownload image
./scripts/download-image.sh
```

### Disk Space Running Out

**Error:** System runs out of disk space

**Solutions:**
```bash
# Check disk usage inside container
docker-compose exec gnu-hurd-dev df -h

# Clean package cache
docker-compose exec gnu-hurd-dev apt-get clean

# Remove unused packages
docker-compose exec gnu-hurd-dev apt-get autoremove

# Check large files
docker-compose exec gnu-hurd-dev du -sh /* | sort -rh

# Clean log files
docker-compose exec gnu-hurd-dev rm -f /var/log/*.log

# On host, check host disk usage
df -h /

# Remove old backups
rm -f debian-hurd-i386-20251105.qcow2.backup
rm -f debian-hurd.img.tar.xz
```

## Performance Issues

### System Very Slow

**Solutions:**
```bash
# Check CPU usage inside container
docker-compose exec gnu-hurd-dev top

# Reduce background processes
docker-compose exec gnu-hurd-dev systemctl disable <service>
docker-compose exec gnu-hurd-dev systemctl stop <service>

# Monitor host CPU usage
top
# Check if QEMU process is high

# Check disk I/O
docker-compose exec gnu-hurd-dev iostat -x 1 5

# Increase host system resources if available
# Or reduce QEMU RAM: -m 1G instead of 1.5G
```

### High CPU Usage

**Solutions:**
```bash
# Check QEMU CPU usage
docker stats gnu-hurd-dev

# Kill runaway processes inside container
docker-compose exec gnu-hurd-dev ps aux | grep -E "bash|python|node"
docker-compose exec gnu-hurd-dev kill -9 <PID>

# Disable unnecessary services
docker-compose exec gnu-hurd-dev systemctl disable <service>

# Check for infinite loops in startup scripts
docker-compose exec gnu-hurd-dev /var/log/syslog | tail -100
```

## Network Configuration Issues

### Can't Access Container from Host

**Error:** Cannot connect to SSH port or custom ports

**Solutions:**
```bash
# Verify port mapping
docker-compose ps

# Test port on localhost
nc -zv localhost 2222      # Should succeed

# Test from host network
curl http://localhost:9999 # If service on 9999

# Check container network
docker inspect gnu-hurd-dev | grep -A 5 "Networks"

# Check firewall on host
sudo ufw status
# If UFW enabled, allow ports
sudo ufw allow 2222
sudo ufw allow 9999
```

### Container Can't Access External Network

**Solutions:**
```bash
# Check container can reach gateway
docker-compose exec gnu-hurd-dev ping 10.0.2.2

# Check Docker networks
docker network ls
docker network inspect hurd-net

# Verify DNS works
docker-compose exec gnu-hurd-dev nslookup google.com

# Check internet connectivity
docker-compose exec gnu-hurd-dev curl https://www.google.com

# If blocked, check host firewall
sudo iptables -L -n | grep FORWARD
```

## General Troubleshooting Steps

### Systematic Debugging

1. **Check logs**
   ```bash
   docker-compose logs --tail=100
   docker-compose logs --since 10m
   ```

2. **Verify resources**
   ```bash
   docker stats gnu-hurd-dev
   df -h /
   free -h
   ```

3. **Test connectivity**
   ```bash
   docker-compose ps
   docker-compose exec gnu-hurd-dev ping 8.8.8.8
   ```

4. **Check service status**
   ```bash
   docker-compose exec gnu-hurd-dev systemctl status ssh
   docker-compose exec gnu-hurd-dev ps aux
   ```

5. **Rebuild and restart**
   ```bash
   docker-compose down -v
   docker-compose build --no-cache
   docker-compose up -d
   ```

## Getting Help

- **Check logs first:** `docker-compose logs`
- **Verify configuration:** `./scripts/validate-config.sh`
- **Search documentation:** See docs/ folder
- **Open GitHub issue:** https://github.com/oaich/gnu-hurd-docker/issues

## References

- [Docker Documentation](https://docs.docker.com/docs/)
- [QEMU Documentation](https://www.qemu.org/documentation/)
- [GNU/Hurd Manual](https://www.gnu.org/software/hurd/documentation.html)
- [Debian GNU/Hurd](https://www.debian.org/ports/hurd/)

---

**Last Updated:** 2025-11-05
**Status:** Complete
