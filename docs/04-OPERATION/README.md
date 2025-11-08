# Operation Guide

**Last Updated**: 2025-11-07
**Section**: 04-OPERATION
**Purpose**: Day-to-day operation and management

---

## Overview

This section covers daily operations for managing the GNU/Hurd x86_64 Docker environment, including interactive access, snapshot management, and system monitoring.

**Audience**: All users (daily operations)

**Prerequisites**: Completed [Getting Started](../01-GETTING-STARTED/) and basic [Configuration](../03-CONFIGURATION/)

---

## Documents in This Section

### [INTERACTIVE-ACCESS.md](INTERACTIVE-ACCESS.md)
**Access methods and daily usage patterns**

- SSH access (primary method)
- Serial console access (emergency)
- Docker exec (container shell, not guest)
- SCP file transfers
- Port forwarding for services
- Screen/tmux sessions

**When to use**: Daily access, file transfers, session management

---

### [SNAPSHOTS.md](SNAPSHOTS.md)
**Snapshot management and state preservation**

- Create snapshots (backup points)
- List snapshots
- Restore snapshots (rollback changes)
- Delete snapshots (cleanup)
- Full backups (export QCOW2)
- Snapshot best practices
- Troubleshooting snapshot issues

**When to use**: Before major changes, state management, rollback

---

### [MONITORING.md](MONITORING.md)
**System monitoring and performance analysis**

- Real-time resource usage (CPU, RAM)
- QEMU performance monitoring
- Log analysis (boot logs, SSH logs)
- Network traffic monitoring
- Disk I/O statistics
- Health checks and alerts

**When to use**: Performance tuning, troubleshooting, capacity planning

---

## Daily Operation Workflows

### Workflow 1: Start/Stop Environment

**Start**:
```bash
# Start container
docker-compose up -d

# Wait for boot (2-5 minutes)
docker-compose logs -f

# Connect via SSH
ssh -p 2222 root@localhost
```

**Stop** (graceful shutdown):
```bash
# Inside guest
shutdown -h now

# Wait for "System halted" message
# Then stop container
docker-compose down
```

**Quick stop** (ungraceful, may cause fsck errors):
```bash
docker-compose down
# Use only when necessary
```

---

### Workflow 2: Work with Snapshots

**Before major changes**:
```bash
# Create snapshot
./scripts/manage-snapshots.sh create before-kernel-build

# Make changes
ssh -p 2222 root@localhost
# [do risky operations]

# If something breaks, restore
./scripts/manage-snapshots.sh restore before-kernel-build

# If successful, delete snapshot
./scripts/manage-snapshots.sh delete before-kernel-build
```

**Regular backup**:
```bash
# Create weekly backup
./scripts/manage-snapshots.sh backup \
  /backup/hurd-$(date +%Y%m%d).qcow2
```

---

### Workflow 3: Monitor Performance

**Real-time monitoring**:
```bash
# Monitor QEMU process
./scripts/monitor-qemu.sh

# Inside guest, monitor resources
ssh -p 2222 root@localhost
htop
# Or: top, vmstat, iostat
```

**Check logs**:
```bash
# Container logs
docker-compose logs | tail -100

# Guest system logs
ssh -p 2222 root@localhost
journalctl -xe
```

---

### Workflow 4: Transfer Files

**SCP** (host ↔ guest):
```bash
# Host to guest
scp -P 2222 local-file.txt root@localhost:/root/

# Guest to host
scp -P 2222 root@localhost:/etc/fstab ./fstab-backup.txt

# Directory recursively
scp -P 2222 -r local-dir/ root@localhost:/root/
```

**SSH pipe** (stream data):
```bash
# Backup database from guest to host
ssh -p 2222 root@localhost "pg_dump mydb" > mydb-backup.sql

# Restore from host to guest
cat mydb-backup.sql | ssh -p 2222 root@localhost "psql mydb"
```

---

## Quick Navigation

**Getting Started**:
- [Installation](../01-GETTING-STARTED/INSTALLATION.md)
- [Quickstart](../01-GETTING-STARTED/QUICKSTART.md)

**Configuration**:
- [Port Forwarding](../03-CONFIGURATION/PORT-FORWARDING.md)
- [User Configuration](../03-CONFIGURATION/USER-CONFIGURATION.md)
- [Custom Features](../03-CONFIGURATION/CUSTOM-FEATURES.md)

**Troubleshooting** (when operations fail):
- [Common Issues](../06-TROUBLESHOOTING/COMMON-ISSUES.md)
- [SSH Issues](../06-TROUBLESHOOTING/SSH-ISSUES.md)
- [Filesystem Errors](../06-TROUBLESHOOTING/FSCK-ERRORS.md)

**Reference**:
- [Scripts](../08-REFERENCE/SCRIPTS.md) - Automation tools
- [Credentials](../08-REFERENCE/CREDENTIALS.md) - Access methods

---

## Operation Best Practices

1. **Always shut down cleanly**:
   ```bash
   # Inside guest
   shutdown -h now
   # Wait for "System halted"
   # Then: docker-compose down
   ```
   **Why**: Prevents filesystem errors (fsck)

2. **Create snapshots before major changes**:
   ```bash
   ./scripts/manage-snapshots.sh create before-upgrade
   ```
   **Why**: Easy rollback if something breaks

3. **Monitor resource usage**:
   ```bash
   ./scripts/monitor-qemu.sh
   ```
   **Why**: Catch performance issues early

4. **Regular backups**:
   ```bash
   # Weekly full backup
   ./scripts/manage-snapshots.sh backup /backup/weekly.qcow2
   ```
   **Why**: Disaster recovery

5. **Check logs regularly**:
   ```bash
   docker-compose logs | grep -i error
   ```
   **Why**: Detect issues before they escalate

---

## Common Operations

### Start Environment
```bash
docker-compose up -d
```

### Stop Environment (Graceful)
```bash
# Inside guest
shutdown -h now
# Then on host
docker-compose down
```

### Restart Environment
```bash
# Graceful
ssh -p 2222 root@localhost shutdown -r now

# Quick (may cause fsck)
docker-compose restart
```

### Access SSH
```bash
ssh -p 2222 root@localhost
```

### Access Serial Console
```bash
telnet localhost 5555
# Or: ./scripts/connect-console.sh
```

### Transfer File
```bash
scp -P 2222 file.txt root@localhost:/root/
```

### Create Snapshot
```bash
./scripts/manage-snapshots.sh create snapshot-name
```

### Restore Snapshot
```bash
./scripts/manage-snapshots.sh restore snapshot-name
```

### Monitor Performance
```bash
./scripts/monitor-qemu.sh
```

### View Logs
```bash
docker-compose logs -f
```

---

## For System Administrators

**Maintenance Schedule**:
- **Daily**: Check logs for errors, verify SSH accessible
- **Weekly**: Create full backup, review disk usage
- **Monthly**: Review performance metrics, clean old snapshots
- **Quarterly**: Update Hurd packages (`apt-get dist-upgrade`)

**Capacity Planning**:
- **Disk**: QCOW2 grows to 80GB max (monitor with `qemu-img info`)
- **RAM**: 4GB recommended minimum, 8GB for desktop/heavy workloads
- **CPU**: 2 cores sufficient, KVM acceleration critical for performance

**Monitoring Metrics**:
- CPU usage: < 50% average (via `monitor-qemu.sh`)
- Memory: < 80% utilized (via `htop` inside guest)
- Disk I/O: < 100 MB/s sustained (via `iostat` inside guest)
- Network: < 1 Gbps sustained (user-mode NAT limitation)

---

## For Developers

**Development Workflows**:
1. **Morning**: Start environment, connect via SSH
2. **Work**: Edit code, build, test (use snapshots before risky changes)
3. **Evening**: Commit changes, shutdown cleanly

**Integration with IDEs**:
- **VS Code Remote SSH**: Configure SSH to port 2222
- **JetBrains Gateway**: Use SSH connection
- **Vim/Emacs**: SSH and edit remotely

**CI/CD Integration**:
- See [CI/CD Setup](../05-CI-CD/SETUP.md)
- Automated testing: [CI/CD Workflows](../05-CI-CD/WORKFLOWS.md)

---

## Troubleshooting Operations

**Container won't start**:
- Check Docker logs: `docker-compose logs`
- Verify QCOW2 image exists: `ls -lh *.qcow2`
- Check disk space: `df -h`

**SSH connection refused**:
- See [SSH Issues](../06-TROUBLESHOOTING/SSH-ISSUES.md)

**Performance degradation**:
- Check resource usage: `./scripts/monitor-qemu.sh`
- See [Monitoring](MONITORING.md)

**Filesystem errors on boot**:
- See [Filesystem Errors](../06-TROUBLESHOOTING/FSCK-ERRORS.md)
- Always use clean shutdown!

---

[← Back to Documentation Index](../INDEX.md)
