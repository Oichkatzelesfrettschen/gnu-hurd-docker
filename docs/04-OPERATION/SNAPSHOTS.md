# GNU/Hurd Docker - Snapshot Management Guide

**Last Updated**: 2025-11-07  
**Consolidated From**:
- scripts/manage-snapshots.sh (snapshot management tool)
- QCOW2 snapshot documentation

**Purpose**: Complete guide to QCOW2 snapshot management for GNU/Hurd images

**Scope**: Debian GNU/Hurd x86_64 only (i386 deprecated 2025-11-07)

---

## Overview

QCOW2 (QEMU Copy-On-Write 2) is the disk image format used for GNU/Hurd guests. It provides:

- **Internal Snapshots**: Fast, space-efficient snapshots stored within the QCOW2 file
- **Copy-on-Write**: Only modified blocks consume additional space
- **Compression**: 50% typical compression ratio
- **Instant Rollback**: Restore to any snapshot in seconds

**Use Cases**:
- Save system state before risky operations
- Create checkpoints during development
- Quick recovery from misconfigurations
- Testing different configurations
- CI/CD pipeline state management

---

## Snapshot Architecture

### QCOW2 Structure

```
┌─────────────────────────────────────────────────┐
│  QCOW2 File: debian-hurd-amd64.qcow2            │
│  ┌───────────────────────────────────────────┐  │
│  │  Base Image Layer (immutable after snap)  │  │
│  └───────────────────────────────────────────┘  │
│                    ↓                             │
│  ┌───────────────────────────────────────────┐  │
│  │  Snapshot 1: "initial-setup"              │  │
│  │  - Metadata: timestamp, VM state          │  │
│  │  - Delta: changed blocks only             │  │
│  └───────────────────────────────────────────┘  │
│                    ↓                             │
│  ┌───────────────────────────────────────────┐  │
│  │  Snapshot 2: "dev-environment"            │  │
│  │  - Builds on Snapshot 1                   │  │
│  │  - Only new changes stored                │  │
│  └───────────────────────────────────────────┘  │
│                    ↓                             │
│  ┌───────────────────────────────────────────┐  │
│  │  Current State (active)                   │  │
│  │  - Working changes                        │  │
│  └───────────────────────────────────────────┘  │
└─────────────────────────────────────────────────┘
```

### Snapshot Types

**Internal Snapshots** (QCOW2 native):
- Stored within the QCOW2 file itself
- Fast creation and restoration (~1-5 seconds)
- Includes VM state (CPU, memory) if VM is running
- No external files needed
- **Used by this project**

**External Snapshots** (separate files):
- Creates new QCOW2 file for delta
- Original file becomes read-only backing file
- More complex management
- Not covered in this guide

---

## Snapshot Management Tool

The repository provides `scripts/manage-snapshots.sh` for snapshot operations.

### Tool Location

```bash
# From repository root
./scripts/manage-snapshots.sh <command> [args]

# Or make it executable and add to PATH
chmod +x scripts/manage-snapshots.sh
export PATH="$PATH:$(pwd)/scripts"
manage-snapshots.sh <command> [args]
```

### Configuration

**Image Path** (edit script if needed):

```bash
# Default: looks for debian-hurd-amd64-*.qcow2 in current directory
IMAGE_PATH="${IMAGE_PATH:-./debian-hurd-amd64-*.qcow2}"

# Or set environment variable:
export IMAGE_PATH=/path/to/my-hurd-image.qcow2
./scripts/manage-snapshots.sh list
```

---

## Snapshot Commands

### Create Snapshot

**Usage:**

```bash
./scripts/manage-snapshots.sh create <snapshot-name>
```

**Examples:**

```bash
# Create snapshot of initial setup
./scripts/manage-snapshots.sh create initial-setup

# Create snapshot after installing development tools
./scripts/manage-snapshots.sh create dev-tools-installed

# Create snapshot with descriptive name
./scripts/manage-snapshots.sh create "before-kernel-upgrade"
```

**Output:**

```
Creating snapshot: initial-setup
Snapshot 'initial-setup' created successfully
```

**What Happens:**
1. QEMU saves current VM state (if running)
2. QCOW2 records current disk state
3. Metadata (timestamp, description) stored
4. VM continues running (no downtime)

**Requirements:**
- VM must be running (QEMU process active)
- Sufficient disk space (~10-50 MB per snapshot typically)
- Write permission to QCOW2 file

### List Snapshots

**Usage:**

```bash
./scripts/manage-snapshots.sh list
```

**Example Output:**

```
Snapshots in: debian-hurd-amd64.qcow2

Snapshot list:
ID        TAG                     VM SIZE    DATE         VM CLOCK
1         initial-setup           0 B        2025-11-07   00:00:00.000
2         dev-tools-installed     450 MB     2025-11-07   00:15:32.123
3         before-kernel-upgrade   450 MB     2025-11-07   01:23:45.678
```

**Column Descriptions:**
- **ID**: Numeric snapshot identifier
- **TAG**: Snapshot name (what you provided)
- **VM SIZE**: RAM snapshot size (0 B if VM was stopped)
- **DATE**: Creation timestamp
- **VM CLOCK**: Guest uptime at snapshot

**Notes:**
- ID 1 is always the earliest snapshot
- VM SIZE = 0 if snapshot taken while VM stopped
- VM SIZE > 0 if snapshot includes running VM state

### Restore Snapshot

**Usage:**

```bash
./scripts/manage-snapshots.sh restore <snapshot-name>
```

**Examples:**

```bash
# Restore to initial setup
./scripts/manage-snapshots.sh restore initial-setup

# Restore to specific development state
./scripts/manage-snapshots.sh restore dev-tools-installed
```

**Output:**

```
Restoring snapshot: initial-setup
WARNING: This will discard all changes since snapshot was created!
Snapshot 'initial-setup' restored successfully
```

**What Happens:**
1. QEMU must be stopped (script will stop it if running)
2. Disk state reverted to snapshot point
3. All changes after snapshot are discarded
4. VM state (CPU, memory) restored if snapshot included it

**⚠️ WARNING**: This is **destructive**. All changes after snapshot creation are lost.

**Requirements:**
- QEMU must be stopped (or script will stop it)
- Snapshot must exist (check with `list`)
- Write permission to QCOW2 file

**Safe Workflow**:

```bash
# 1. Create current state snapshot before restoring
./scripts/manage-snapshots.sh create before-restore-$(date +%Y%m%d-%H%M%S)

# 2. Now safe to restore
./scripts/manage-snapshots.sh restore initial-setup

# 3. If restore was wrong, can go back
./scripts/manage-snapshots.sh restore before-restore-20251107-143052
```

### Delete Snapshot

**Usage:**

```bash
./scripts/manage-snapshots.sh delete <snapshot-name>
```

**Examples:**

```bash
# Delete old snapshot
./scripts/manage-snapshots.sh delete initial-setup

# Delete temporary snapshot
./scripts/manage-snapshots.sh delete temp-test-snapshot
```

**Output:**

```
Deleting snapshot: initial-setup
Snapshot 'initial-setup' deleted successfully
```

**What Happens:**
1. Snapshot metadata removed from QCOW2
2. Disk space may be reclaimed (depends on QCOW2 internals)
3. Cannot restore to this snapshot anymore

**⚠️ WARNING**: Deletion is **permanent**. Cannot undo.

**Safe Practice**:
- Only delete snapshots you're certain you don't need
- Keep at least one "known-good" snapshot
- Export snapshots before deletion if unsure (see backup section)

### Backup Snapshot (Export)

**Usage:**

```bash
./scripts/manage-snapshots.sh backup <snapshot-name> <output-file>
```

**Examples:**

```bash
# Export snapshot to compressed archive
./scripts/manage-snapshots.sh backup initial-setup backups/initial-setup.qcow2.gz

# Export to uncompressed file
./scripts/manage-snapshots.sh backup dev-tools-installed backups/dev-tools.qcow2
```

**What Happens:**
1. Creates full QCOW2 image at snapshot state
2. Optionally compresses with gzip (if .gz extension)
3. Suitable for archiving or transfer

**Output File Format:**
- `.qcow2` - Uncompressed QCOW2 image
- `.qcow2.gz` - Gzip-compressed QCOW2 image

**Disk Space:**
- Uncompressed: ~4 GB (full guest disk size)
- Compressed: ~2 GB (50% compression typical)

**Use Cases:**
- Long-term archival
- Transfer to another system
- Off-site backup
- Version control of system states

**Restoring from Backup:**

```bash
# Decompress if needed
gunzip backups/initial-setup.qcow2.gz

# Replace current image
cp backups/initial-setup.qcow2 debian-hurd-amd64.qcow2

# Restart QEMU
docker-compose restart
```

---

## Snapshot Workflows

### Workflow 1: Safe System Upgrade

```bash
# 1. Create pre-upgrade snapshot
./scripts/manage-snapshots.sh create before-upgrade-$(date +%Y%m%d)

# 2. Perform upgrade (via SSH)
ssh -p 2222 root@localhost
apt-get update
apt-get dist-upgrade
exit

# 3. Test system
ssh -p 2222 root@localhost
# Run tests, check functionality

# 4. If upgrade failed, restore
./scripts/manage-snapshots.sh restore before-upgrade-20251107

# 5. If upgrade succeeded, can delete old snapshots
./scripts/manage-snapshots.sh delete before-upgrade-20251107
```

### Workflow 2: Development Checkpoints

```bash
# Day 1: Fresh system
./scripts/manage-snapshots.sh create day1-fresh-install

# Day 2: Installed development tools
ssh -p 2222 root@localhost 'apt-get install -y gcc make git'
./scripts/manage-snapshots.sh create day2-dev-tools

# Day 3: Built project
ssh -p 2222 root@localhost 'cd /project && make'
./scripts/manage-snapshots.sh create day3-project-built

# Day 4: Made breaking changes, need to rollback
./scripts/manage-snapshots.sh restore day3-project-built
```

### Workflow 3: CI/CD Pipeline Integration

```bash
#!/bin/bash
# ci-test.sh

set -e

IMAGE="debian-hurd-amd64.qcow2"
SNAPSHOT_NAME="ci-test-$(date +%Y%m%d-%H%M%S)"

# 1. Start with clean snapshot
./scripts/manage-snapshots.sh restore ci-baseline

# 2. Start VM
docker-compose up -d

# 3. Wait for boot
sleep 120

# 4. Run tests
ssh -p 2222 root@localhost '/mnt/host/run-tests.sh'

# 5. Collect results
scp -P 2222 root@localhost:/test-results.xml ./

# 6. Create success snapshot if tests passed
if [ -f test-results.xml ]; then
    ./scripts/manage-snapshots.sh create "$SNAPSHOT_NAME"
fi

# 7. Cleanup: restore to baseline
./scripts/manage-snapshots.sh restore ci-baseline

# 8. Shutdown
docker-compose down
```

### Workflow 4: Snapshot Archival Strategy

```bash
#!/bin/bash
# Monthly archival of important snapshots

BACKUP_DIR="backups/$(date +%Y-%m)"
mkdir -p "$BACKUP_DIR"

# Archive production snapshots
for snapshot in production-baseline production-stable; do
    if ./scripts/manage-snapshots.sh list | grep -q "$snapshot"; then
        echo "Archiving $snapshot..."
        ./scripts/manage-snapshots.sh backup "$snapshot" \
            "$BACKUP_DIR/${snapshot}-$(date +%Y%m%d).qcow2.gz"
    fi
done

# Delete old snapshots (older than 30 days)
find backups/ -name "*.qcow2.gz" -mtime +30 -delete

echo "Archival complete. Backups stored in $BACKUP_DIR"
```

---

## Advanced Snapshot Operations

### Using QEMU Monitor (Manual Control)

If `manage-snapshots.sh` is unavailable, use QEMU Monitor directly:

**Connect to Monitor:**

```bash
telnet localhost 9999
```

**List Snapshots:**

```
(qemu) info snapshots
Snapshot list:
ID        TAG                     VM SIZE    DATE         VM CLOCK
1         initial-setup           0 B        2025-11-07   00:00:00.000
2         dev-tools-installed     450 MB     2025-11-07   00:15:32.123
```

**Create Snapshot:**

```
(qemu) savevm snapshot-name
```

**Restore Snapshot:**

```
(qemu) loadvm snapshot-name
```

**Delete Snapshot:**

```
(qemu) delvm snapshot-name
```

### Using qemu-img (Offline Operations)

For operations when VM is stopped:

**List Snapshots:**

```bash
qemu-img snapshot -l debian-hurd-amd64.qcow2
```

**Create Snapshot (offline only):**

```bash
# Stop VM first
docker-compose down

# Create snapshot
qemu-img snapshot -c snapshot-name debian-hurd-amd64.qcow2

# Restart VM
docker-compose up -d
```

**Restore Snapshot (offline only):**

```bash
# Stop VM
docker-compose down

# Restore
qemu-img snapshot -a snapshot-name debian-hurd-amd64.qcow2

# Restart VM
docker-compose up -d
```

**Delete Snapshot:**

```bash
# Can be done online or offline
qemu-img snapshot -d snapshot-name debian-hurd-amd64.qcow2
```

**Convert QCOW2 to Raw (extract data):**

```bash
qemu-img convert -f qcow2 -O raw \
    debian-hurd-amd64.qcow2 \
    debian-hurd-amd64.raw
```

---

## Snapshot Best Practices

### Naming Conventions

**Good Names:**
- `initial-setup` - Descriptive, readable
- `dev-tools-installed` - Clear purpose
- `before-upgrade-20251107` - Includes date
- `ci-baseline` - Indicates use case
- `production-stable-v1.2` - Includes version

**Bad Names:**
- `snap1` - Not descriptive
- `test` - Ambiguous
- `abc` - Meaningless
- ` spaces in name` - Avoid spaces (use hyphens)

### Snapshot Lifecycle Management

**Keep:**
- ✅ Baseline (clean install)
- ✅ Major milestones (project completion)
- ✅ Pre-upgrade snapshots (until verified)
- ✅ Known-good states (last working version)

**Delete:**
- ❌ Old test snapshots
- ❌ Temporary checkpoints (after merge)
- ❌ Superseded baselines (after new baseline)
- ❌ Failed experiments

**Archive (Export to Backup):**
- Long-term baselines
- Production releases
- Compliance/audit snapshots
- Cross-system migration

### Disk Space Management

**Monitor Disk Usage:**

```bash
# Check QCOW2 file size
du -h debian-hurd-amd64.qcow2
# Example: 3.2G (with snapshots)

# Check actual disk usage vs. virtual size
qemu-img info debian-hurd-amd64.qcow2
# virtual size: 20 GiB (...)
# disk size: 3.2 GiB (actual)
```

**Reclaim Space (after deleting snapshots):**

```bash
# Convert to new QCOW2 to reclaim space
qemu-img convert -O qcow2 \
    debian-hurd-amd64.qcow2 \
    debian-hurd-amd64-compact.qcow2

# Verify size reduction
du -h debian-hurd-amd64-compact.qcow2

# Replace original (VM must be stopped)
docker-compose down
mv debian-hurd-amd64.qcow2 debian-hurd-amd64-old.qcow2
mv debian-hurd-amd64-compact.qcow2 debian-hurd-amd64.qcow2
docker-compose up -d

# Delete old file after verification
rm debian-hurd-amd64-old.qcow2
```

### Performance Considerations

**Snapshot Speed:**
- Create: 1-5 seconds (instant)
- Restore: 1-5 seconds (instant)
- Delete: 1-5 seconds (instant)
- Export: 1-5 minutes (depends on disk speed)

**Snapshot Impact:**
- Minimal performance impact (copy-on-write overhead)
- No downtime for create/delete
- Brief pause (~1 second) for restore
- More snapshots = slightly larger QCOW2 file

**Optimization:**
- Limit snapshots to 10-20 per image
- Delete old snapshots regularly
- Compress exports with gzip
- Use separate QCOW2 files for different projects

---

## Troubleshooting Snapshots

### Problem: "Snapshot creation failed"

**Diagnosis:**

```bash
# Check QEMU is running
docker-compose ps
# Expected: hurd-x86_64-qemu Up

# Check disk space
df -h .
# Need at least 1 GB free

# Check QCOW2 permissions
ls -lh debian-hurd-amd64.qcow2
# Should be writable
```

**Fix:**

```bash
# Free up disk space
docker system prune

# Fix permissions
chmod 644 debian-hurd-amd64.qcow2

# Retry
./scripts/manage-snapshots.sh create test-snapshot
```

### Problem: "Snapshot not found"

**Diagnosis:**

```bash
# List all snapshots
./scripts/manage-snapshots.sh list

# Or via qemu-img
qemu-img snapshot -l debian-hurd-amd64.qcow2
```

**Fix:**

```bash
# Check exact snapshot name (case-sensitive)
./scripts/manage-snapshots.sh list | grep -i "initial"

# Use correct name
./scripts/manage-snapshots.sh restore initial-setup
```

### Problem: "Cannot restore while VM is running"

**Diagnosis:**

```bash
# Check if QEMU process is running
docker-compose ps
# If "Up", VM is running
```

**Fix (Option 1 - Graceful):**

```bash
# Shutdown VM gracefully
ssh -p 2222 root@localhost 'shutdown -h now'

# Wait for shutdown
sleep 30

# Restore snapshot
./scripts/manage-snapshots.sh restore snapshot-name

# Restart VM
docker-compose up -d
```

**Fix (Option 2 - Force):**

```bash
# Stop container (forceful)
docker-compose down

# Restore snapshot (offline)
qemu-img snapshot -a snapshot-name debian-hurd-amd64.qcow2

# Restart
docker-compose up -d
```

### Problem: "Snapshot restore corrupts filesystem"

**Symptoms:**
- Boot fails after restore
- Filesystem errors on boot
- Data inconsistency

**Cause:**
- Snapshot taken while filesystem had pending writes
- Disk cache not flushed

**Prevention:**

```bash
# Inside guest, flush filesystem before snapshot
sync
sync
sync

# Or stop VM gracefully
shutdown -h now

# Then create snapshot
```

**Recovery:**

```bash
# Boot to serial console
telnet localhost 5555

# Run fsck
fsck.ext2 /dev/sda1

# Or from host (VM must be stopped)
docker-compose down
qemu-nbd -c /dev/nbd0 debian-hurd-amd64.qcow2
fsck.ext2 /dev/nbd0p1
qemu-nbd -d /dev/nbd0
docker-compose up -d
```

### Problem: "QCOW2 file is growing too large"

**Diagnosis:**

```bash
# Check file size
du -h debian-hurd-amd64.qcow2
# Example: 8.5G (too large)

# Check virtual vs. actual
qemu-img info debian-hurd-amd64.qcow2
# virtual size: 20 GiB
# disk size: 8.5 GiB

# Count snapshots
qemu-img snapshot -l debian-hurd-amd64.qcow2 | wc -l
# Example: 25 snapshots (too many)
```

**Fix:**

```bash
# Delete old snapshots
for i in {1..15}; do
    ./scripts/manage-snapshots.sh delete old-snapshot-$i
done

# Compact QCOW2 (offline only)
docker-compose down
qemu-img convert -O qcow2 -c \
    debian-hurd-amd64.qcow2 \
    debian-hurd-amd64-compact.qcow2

# Replace
mv debian-hurd-amd64.qcow2 debian-hurd-amd64-old.qcow2
mv debian-hurd-amd64-compact.qcow2 debian-hurd-amd64.qcow2

# Restart
docker-compose up -d

# Verify size reduction
du -h debian-hurd-amd64.qcow2
# Expected: < 4 GB
```

---

## Integration with Other Tools

### Git-Like Workflow

Treat snapshots as "commits":

```bash
# Current "branch" = running system
# "Commit" = create snapshot

# Make changes
ssh -p 2222 root@localhost 'echo "test" > /tmp/test.txt'

# "Commit" changes
./scripts/manage-snapshots.sh create "feature-added-test-file"

# Make more changes
ssh -p 2222 root@localhost 'rm /tmp/test.txt'

# "Revert" to previous commit
./scripts/manage-snapshots.sh restore "feature-added-test-file"

# Changes are undone
ssh -p 2222 root@localhost 'ls /tmp/test.txt'
# File exists again
```

### Automated Snapshot Rotation

**Daily Rotation Script:**

```bash
#!/bin/bash
# snapshot-rotate.sh - Keep last 7 daily snapshots

DAILY_NAME="daily-$(date +%Y%m%d)"
KEEP_DAYS=7

# Create today's snapshot
./scripts/manage-snapshots.sh create "$DAILY_NAME"

# Delete snapshots older than KEEP_DAYS
./scripts/manage-snapshots.sh list | \
    grep "^[0-9]" | \
    awk '{print $2}' | \
    grep "^daily-" | \
    sort -r | \
    tail -n +$((KEEP_DAYS + 1)) | \
    while read snapshot; do
        echo "Deleting old snapshot: $snapshot"
        ./scripts/manage-snapshots.sh delete "$snapshot"
    done
```

**Add to Crontab:**

```bash
# Run daily at 2 AM
0 2 * * * /path/to/snapshot-rotate.sh
```

### Snapshot Comparison

**Compare two snapshots:**

```bash
#!/bin/bash
# snapshot-diff.sh - Show differences between two snapshots

SNAPSHOT1="$1"
SNAPSHOT2="$2"

# Export both snapshots
./scripts/manage-snapshots.sh backup "$SNAPSHOT1" /tmp/snap1.qcow2
./scripts/manage-snapshots.sh backup "$SNAPSHOT2" /tmp/snap2.qcow2

# Mount both (requires qemu-nbd)
modprobe nbd max_part=8
qemu-nbd -c /dev/nbd0 /tmp/snap1.qcow2
qemu-nbd -c /dev/nbd1 /tmp/snap2.qcow2

mkdir -p /mnt/snap1 /mnt/snap2
mount /dev/nbd0p1 /mnt/snap1
mount /dev/nbd1p1 /mnt/snap2

# Diff
diff -r /mnt/snap1 /mnt/snap2

# Cleanup
umount /mnt/snap1 /mnt/snap2
qemu-nbd -d /dev/nbd0
qemu-nbd -d /dev/nbd1
rm /tmp/snap1.qcow2 /tmp/snap2.qcow2
```

---

## Reference

### manage-snapshots.sh Command Summary

```bash
# Create snapshot
./scripts/manage-snapshots.sh create <name>

# List snapshots
./scripts/manage-snapshots.sh list

# Restore snapshot
./scripts/manage-snapshots.sh restore <name>

# Delete snapshot
./scripts/manage-snapshots.sh delete <name>

# Export snapshot
./scripts/manage-snapshots.sh backup <name> <output-file>
```

### qemu-img Snapshot Commands

```bash
# List snapshots
qemu-img snapshot -l <image.qcow2>

# Create snapshot (offline)
qemu-img snapshot -c <snapshot-name> <image.qcow2>

# Restore snapshot (offline)
qemu-img snapshot -a <snapshot-name> <image.qcow2>

# Delete snapshot
qemu-img snapshot -d <snapshot-name> <image.qcow2>

# Convert/compact
qemu-img convert -O qcow2 <input> <output>

# Info
qemu-img info <image.qcow2>

# Check integrity
qemu-img check <image.qcow2>
```

### QEMU Monitor Snapshot Commands

```bash
# Connect
telnet localhost 9999

# List
(qemu) info snapshots

# Create
(qemu) savevm <snapshot-name>

# Restore
(qemu) loadvm <snapshot-name>

# Delete
(qemu) delvm <snapshot-name>
```

### Environment Variables

```bash
# Override image path
export IMAGE_PATH=/path/to/image.qcow2
./scripts/manage-snapshots.sh list

# Override QEMU monitor port
export MONITOR_PORT=9999
telnet localhost $MONITOR_PORT
```

### File Paths

**Host:**
- Script: `./scripts/manage-snapshots.sh`
- Image: `./debian-hurd-amd64-*.qcow2`
- Backups: `./backups/` (user-defined)

**Container:**
- Image: `/opt/hurd-image/debian-hurd-amd64.qcow2`
- QEMU Monitor: `telnet:0.0.0.0:9999`

---

## Security Considerations

**Snapshots Contain:**
- ✅ Full disk state (all files, configs, logs)
- ✅ User passwords (hashed in /etc/shadow)
- ✅ SSH keys (if stored in guest)
- ✅ Application secrets
- ✅ VM memory (CPU registers, RAM) if running

**⚠️ Security Implications:**
- Snapshots are **not encrypted** by default
- Exporting snapshots exposes all data
- Archived snapshots should be stored securely
- Delete snapshots when no longer needed

**Secure Practices:**
- Encrypt snapshot exports: `gpg -c snapshot.qcow2.gz`
- Restrict access to QCOW2 files: `chmod 600 debian-hurd-amd64.qcow2`
- Store backups on encrypted volumes
- Audit snapshot access logs
- Delete snapshots before sharing images

---

**Status**: Production Ready (x86_64-only)  
**Last Updated**: 2025-11-07  
**Architecture**: Pure x86_64  
**Snapshot Format**: QCOW2 internal snapshots
