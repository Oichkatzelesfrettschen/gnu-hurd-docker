# Troubleshooting Guide

**Last Updated**: 2025-11-07
**Section**: 06-TROUBLESHOOTING
**Purpose**: Diagnose and fix common issues

---

## Overview

This section provides comprehensive troubleshooting guides for common issues encountered with the GNU/Hurd x86_64 Docker environment.

**Audience**: All users (when things go wrong)

**Quick Links**: Jump directly to most common issues below

---

## Documents in This Section

### [COMMON-ISSUES.md](COMMON-ISSUES.md)
**Most frequently encountered problems and solutions**

- Container won't start
- QEMU boot failures
- Network connectivity issues
- Performance problems
- Disk space errors
- Port conflicts
- Permission denied errors

**When to use**: First stop for any issue, covers 80% of problems

---

### [SSH-ISSUES.md](SSH-ISSUES.md)
**SSH connection and authentication problems**

- Connection refused
- Password rejected
- Permission denied (publickey)
- Host key verification failed
- SSH hangs or timeouts
- SCP/SFTP failures
- Port forwarding not working

**When to use**: Cannot connect via SSH (most common issue)

---

### [FSCK-ERRORS.md](FSCK-ERRORS.md)
**Filesystem consistency errors and repair**

- "Unexpected inconsistency; RUN fsck MANUALLY"
- Filesystem check errors on boot
- Manual fsck procedures
- Emergency mode recovery
- Clean shutdown practices
- Preventing fsck errors

**When to use**: System drops to emergency mode, filesystem errors on boot

---

## Quick Diagnosis

### Issue: Cannot SSH to Guest

**Symptom**: `ssh -p 2222 root@localhost` fails

**Go to**: [SSH-ISSUES.md](SSH-ISSUES.md)

**Quick fixes**:
1. Check container running: `docker-compose ps`
2. Check SSH service: Use serial console
3. Verify port: `docker-compose ps | grep 2222`

---

### Issue: Boot Drops to Emergency Mode

**Symptom**: "EMERGENCY MODE", "fsck errors", "filesystem check forced"

**Go to**: [FSCK-ERRORS.md](FSCK-ERRORS.md)

**Quick fix**:
```bash
# At emergency prompt
/sbin/fsck.ext2 -y /dev/sd0s2
reboot
```

---

### Issue: Container Won't Start

**Symptom**: `docker-compose up -d` fails

**Go to**: [COMMON-ISSUES.md](COMMON-ISSUES.md#container-wont-start)

**Quick fixes**:
1. Check logs: `docker-compose logs`
2. Verify image exists: `ls -lh *.qcow2`
3. Check disk space: `df -h`

---

### Issue: Performance is Slow

**Symptom**: Boot takes > 10 minutes, SSH lags

**Go to**: [COMMON-ISSUES.md](COMMON-ISSUES.md#performance-issues)

**Quick fixes**:
1. Check acceleration: KVM vs TCG
2. Increase RAM: Edit docker-compose.yml (4GB → 8GB)
3. Monitor resources: `./scripts/monitor-qemu.sh`

---

## Troubleshooting Decision Tree

```
Problem?
│
├─ Cannot SSH
│  ├─ Container not running? → docker-compose up -d
│  ├─ SSH service down? → Use serial console, systemctl restart ssh
│  └─ Password wrong? → Try empty password or 'root'
│
├─ Boot failures
│  ├─ Drops to emergency mode? → Run fsck (see FSCK-ERRORS.md)
│  ├─ QEMU crashes? → Check logs (docker-compose logs)
│  └─ Hangs on boot? → Wait 5 minutes or check KVM/TCG
│
├─ Network issues
│  ├─ No internet inside guest? → Check dhclient eth0
│  ├─ DNS not resolving? → Add nameservers to /etc/resolv.conf
│  └─ Port forwarding broken? → Verify docker-compose.yml ports
│
└─ Performance issues
   ├─ Slow boot? → Check KVM acceleration
   ├─ High CPU usage? → Reduce SMP cores (2 → 1)
   └─ Out of RAM? → Increase QEMU_RAM in docker-compose.yml
```

---

## Quick Navigation

**Getting Started** (if setup incomplete):
- [Installation](../01-GETTING-STARTED/INSTALLATION.md)
- [Quickstart](../01-GETTING-STARTED/QUICKSTART.md)

**Architecture** (understand system):
- [System Design](../02-ARCHITECTURE/SYSTEM-DESIGN.md)
- [QEMU Configuration](../02-ARCHITECTURE/QEMU-CONFIGURATION.md)

**Operation** (daily usage):
- [Interactive Access](../04-OPERATION/INTERACTIVE-ACCESS.md)
- [Snapshots](../04-OPERATION/SNAPSHOTS.md) - Restore working state
- [Monitoring](../04-OPERATION/MONITORING.md)

**Reference**:
- [Scripts](../08-REFERENCE/SCRIPTS.md) - Diagnostic tools
- [Credentials](../08-REFERENCE/CREDENTIALS.md) - Default passwords

---

## Common Error Messages

### "Connection refused"
**File**: [SSH-ISSUES.md](SSH-ISSUES.md#connection-refused)

**Meaning**: SSH service not running or port not forwarded

**Quick fix**:
```bash
# Check container
docker-compose ps

# Check SSH service (via serial console)
telnet localhost 5555
# login: root
systemctl status ssh
systemctl restart ssh
```

---

### "Permission denied (publickey,password)"
**File**: [SSH-ISSUES.md](SSH-ISSUES.md#password-rejected)

**Meaning**: Wrong password or password auth disabled

**Quick fix**:
```bash
# Try empty password (press Enter only)
ssh -p 2222 root@localhost

# Or enable password auth (via serial console)
sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
systemctl restart ssh
```

---

### "Unexpected inconsistency; RUN fsck MANUALLY"
**File**: [FSCK-ERRORS.md](FSCK-ERRORS.md#quick-fix)

**Meaning**: Filesystem corruption (usually from unclean shutdown)

**Quick fix**:
```bash
# At emergency prompt
/sbin/fsck.ext2 -y /dev/sd0s2
reboot
```

---

### "Cannot allocate memory"
**File**: [COMMON-ISSUES.md](COMMON-ISSUES.md#out-of-memory)

**Meaning**: Insufficient RAM allocated to QEMU

**Quick fix**:
```yaml
# Edit docker-compose.yml
environment:
  QEMU_RAM: 8192  # Increase from 4096 to 8192
```

---

### "Port already in use"
**File**: [COMMON-ISSUES.md](COMMON-ISSUES.md#port-conflicts)

**Meaning**: Host port 2222 or 5555 already occupied

**Quick fix**:
```bash
# Find process using port
lsof -i :2222

# Kill process or change port in docker-compose.yml
# ports:
#   - "3333:22"  # Use 3333 instead of 2222
```

---

## Prevention Best Practices

1. **Always shut down cleanly** ([Operation](../04-OPERATION/))
   ```bash
   # Inside guest
   shutdown -h now
   # Wait for "System halted"
   docker-compose down
   ```
   **Prevents**: Filesystem errors, data corruption

2. **Create snapshots before major changes** ([Snapshots](../04-OPERATION/SNAPSHOTS.md))
   ```bash
   ./scripts/manage-snapshots.sh create before-upgrade
   ```
   **Prevents**: Irreversible mistakes, data loss

3. **Monitor resource usage** ([Monitoring](../04-OPERATION/MONITORING.md))
   ```bash
   ./scripts/monitor-qemu.sh
   ```
   **Prevents**: Performance degradation, crashes

4. **Keep QCOW2 image backed up** ([Snapshots](../04-OPERATION/SNAPSHOTS.md))
   ```bash
   ./scripts/manage-snapshots.sh backup /backup/hurd.qcow2
   ```
   **Prevents**: Total data loss

5. **Use pre-provisioned images in CI** ([CI/CD](../05-CI-CD/PROVISIONED-IMAGE.md))
   ```
   Reliability: 95%+ vs 60-70% with serial automation
   ```
   **Prevents**: CI failures, flaky tests

---

## Diagnostic Tools

### Container Diagnostics
```bash
# Check container status
docker-compose ps

# View logs
docker-compose logs | tail -100

# Enter container shell (NOT guest!)
docker-compose exec hurd-x86_64 /bin/bash
```

---

### Guest Diagnostics (via SSH)
```bash
# System info
uname -a

# Resource usage
htop
# Or: top, vmstat, free -h

# Disk usage
df -h

# Network status
ifconfig
# Or: ip addr show

# Service status
systemctl status ssh
```

---

### Host Diagnostics
```bash
# QEMU process
ps aux | grep qemu-system-x86_64

# Port forwarding
lsof -i :2222
lsof -i :5555

# Disk space
df -h

# Docker status
docker ps
docker stats
```

---

## Recovery Procedures

### Recover from Broken State

**Method 1: Restore snapshot**
```bash
./scripts/manage-snapshots.sh list
./scripts/manage-snapshots.sh restore clean-state
```

**Method 2: Repair filesystem**
```bash
# Via serial console
telnet localhost 5555
# login: root
/sbin/fsck.ext2 -y /dev/sd0s2
reboot
```

**Method 3: Start fresh** (last resort)
```bash
# Backup important data first (via SSH or SCP)
# Then download fresh image
./scripts/setup-hurd-amd64.sh
docker-compose up -d
```

---

### Recover SSH Access

**Method 1: Serial console**
```bash
telnet localhost 5555
# login: root
# Install/restart SSH
apt-get update
apt-get install -y openssh-server random-egd
systemctl restart ssh
```

**Method 2: Restore provisioned image**
```bash
# Replace with pre-provisioned backup
cp hurd-provisioned-backup.qcow2 debian-hurd-amd64-80gb.qcow2
docker-compose restart
```

---

## For System Administrators

**Escalation Path**:
1. **Check this section first** (solves 80% of issues)
2. **Check logs** (`docker-compose logs`)
3. **Try serial console** (emergency access)
4. **Restore snapshot** (known good state)
5. **Consult Research section** (deep dives, advanced troubleshooting)

**Documentation Priority**:
- **Common Issues**: Start here
- **SSH Issues**: Most frequent problem
- **Filesystem Errors**: Boot failures
- **Architecture docs**: Complex issues requiring system understanding

---

## For Developers

**Debug Workflows**:
1. **Reproduce locally**: Use same Docker/QEMU versions
2. **Enable verbose logging**: QEMU debug flags
3. **Use serial console**: Watch boot messages
4. **Bisect changes**: Restore snapshots, test incrementally

**Test Isolation**:
- Create snapshot before each test
- Restore after failure
- Automated with CI/CD scripts

---

[← Back to Documentation Index](../INDEX.md)
