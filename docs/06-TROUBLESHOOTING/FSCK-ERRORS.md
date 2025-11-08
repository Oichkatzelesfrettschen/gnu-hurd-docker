# GNU/Hurd Docker - Filesystem Errors (fsck)

**Last Updated**: 2025-11-07
**Consolidated From**:
- FSCK-ERROR-FIX.md (filesystem repair guide)

**Purpose**: Diagnose and fix filesystem consistency errors

**Scope**: Debian GNU/Hurd x86_64 only (i386 deprecated 2025-11-07)

---

## Overview

Filesystem errors occur when GNU/Hurd detects inconsistencies on the boot partition, typically due to:

1. **Unclean shutdown**: QEMU terminated without graceful shutdown
2. **Power loss**: Host system crashed or lost power
3. **QCOW2 corruption**: Disk image file damaged
4. **First boot**: Filesystem needs initial check

**This is normal and fixable** - manual intervention required.

---

## Common Error Messages

### Error at Boot

```
unexpected inconsistency; RUN fsck MANUALLY
fsck.ext2: /dev/hd0s2: Superblock has invalid timestamp
/dev/hd0s2 contains a file system with errors, check forced

*** EMERGENCY MODE ***
```

**Device Names** (may vary):
- `/dev/hd0s2` - IDE disk, partition 2 (rare on x86_64)
- `/dev/sd0s2` - SATA disk, partition 2 (common on x86_64)
- `/dev/vda1` - VirtIO disk, partition 1

**What this means**: The filesystem needs repair before the system can boot.

---

## Quick Fix (Interactive fsck)

### Solution 1: Run fsck at Emergency Prompt

When you see the fsck error, you'll be dropped to a prompt (emergency mode or recovery shell).

**Steps**:

```bash
# 1. At the emergency prompt, run fsck with auto-repair
/sbin/fsck.ext2 -y /dev/hd0s2

# Or if device is sd0 (SATA):
/sbin/fsck.ext2 -y /dev/sd0s2

# Or generic fsck (auto-detects filesystem type):
/sbin/fsck -y /dev/hd0s2

# 2. Wait for fsck to complete (1-5 minutes)
# Output will show: "FILE SYSTEM WAS MODIFIED"

# 3. Reboot
reboot
```

**Flags explained**:
- `-y`: Automatically answer "yes" to all repair prompts
- `/dev/hd0s2` or `/dev/sd0s2`: The boot partition (check error message for exact device)

**Expected Output**:

```
Pass 1: Checking inodes, blocks, and sizes
Pass 2: Checking directory structure
Pass 3: Checking directory connectivity
Pass 4: Checking reference counts
Pass 5: Checking group summary information

/dev/hd0s2: ***** FILE SYSTEM WAS MODIFIED *****
/dev/hd0s2: 12345/123456 files (2.3% non-contiguous), 234567/345678 blocks
```

**Next Boot**: System should boot cleanly without errors.

---

## Alternative Methods

### Solution 2: Manual Interactive fsck

If you prefer to answer each repair prompt manually:

```bash
# Run fsck without -y flag
/sbin/fsck.ext2 /dev/hd0s2

# Answer prompts:
Fix <problem>? yes
Clear <inode>? yes
Salvage <file>? yes

# After all repairs, reboot
reboot
```

**When to use**: If you want to review each issue before fixing (slower, more control).

---

### Solution 3: Boot to Single User Mode

If the filesystem won't mount at all:

**At GRUB menu**:

1. **Press `e`** to edit boot entry
2. **Find the kernel line** (starts with `linux` or `kernel`)
3. **Add to end of line**: `single` or `1`
4. **Press Ctrl+X** to boot with changes

**Inside single-user mode**:

```bash
# Filesystem should be mounted read-only
# Run fsck manually
/sbin/fsck.ext2 -y /dev/hd0s2

# Remount read-write if needed
mount -o remount,rw /

# Reboot
reboot
```

**When to use**: When the system can't boot at all, or drops to recovery shell.

---

### Solution 4: Fix from Host (Before Boot)

If QEMU won't boot at all, repair the QCOW2 image from the host machine:

**On host**:

```bash
# 1. Stop QEMU if running
docker-compose down
# or
pkill qemu-system-x86_64

# 2. Check QCOW2 integrity
qemu-img check debian-hurd-amd64-80gb.qcow2

# Output:
# - "No errors were found" (good)
# - "X errors were found" (needs repair)

# 3. Repair QCOW2 image
qemu-img check -r all debian-hurd-amd64-80gb.qcow2

# 4. If still broken, try converting
qemu-img convert -f qcow2 -O raw \
    debian-hurd-amd64-80gb.qcow2 \
    temp.img

qemu-img convert -f raw -O qcow2 \
    temp.img \
    debian-hurd-amd64-80gb-repaired.qcow2

rm temp.img

# 5. Replace corrupted image
mv debian-hurd-amd64-80gb.qcow2 debian-hurd-amd64-80gb.qcow2.corrupt
mv debian-hurd-amd64-80gb-repaired.qcow2 debian-hurd-amd64-80gb.qcow2

# 6. Restart QEMU
docker-compose up -d
```

**When to use**: When QEMU hangs completely or the QCOW2 file is damaged.

---

## Prevention: Clean Shutdown Procedures

### Proper Shutdown (Recommended)

**Always shut down cleanly to prevent filesystem errors.**

**Inside GNU/Hurd guest** (via SSH or serial console):

```bash
# Graceful shutdown
shutdown -h now

# Wait for message: "System halted"
# OR: "QEMU: Terminating on signal 15 from pid..."
```

**Then stop QEMU** (via monitor or Docker):

```bash
# Via Docker Compose
docker-compose down

# Or via QEMU monitor (if accessible)
# Ctrl+Alt+2 (in VNC/GTK window), then:
quit
```

**Time**: 30-60 seconds for complete shutdown

**Result**: Clean shutdown, no fsck errors on next boot

---

### Emergency Shutdown (If Guest Unresponsive)

**If Hurd is unresponsive** (cannot SSH or access serial console):

**Option 1: QEMU Monitor (Graceful)**:

```bash
# Via serial console or monitor
# Send ACPI power button event
system_powerdown

# Wait 30 seconds for shutdown
sleep 30

# Then quit QEMU
quit
```

**Option 2: Docker Stop (Graceful)**:

```bash
# Send SIGTERM to container (gives 10 seconds for shutdown)
docker-compose stop

# Or force stop after timeout
docker-compose stop -t 30
```

**Option 3: QEMU Kill (Last Resort, WILL CAUSE FSCK)**:

```bash
# Only if above methods fail
pkill qemu-system-x86_64

# OR
docker-compose kill
```

**Warning**: Killing QEMU abruptly WILL cause fsck errors on next boot. Use only when necessary.

---

### Automated Clean Shutdown in entrypoint.sh

**Add shutdown handler** to catch signals:

```bash
#!/bin/bash
set -e

# Trap SIGTERM and SIGINT
cleanup() {
    echo "[INFO] Received shutdown signal, stopping QEMU gracefully..."
    # Send ACPI powerdown to QEMU
    echo "system_powerdown" | nc localhost 9999 || true
    sleep 30
    exit 0
}

trap cleanup SIGTERM SIGINT

# Start QEMU
exec qemu-system-x86_64 \
    -monitor telnet:0.0.0.0:9999,server,nowait \
    ...
```

**Result**: Docker stop triggers graceful QEMU shutdown, reducing fsck errors.

---

## Troubleshooting fsck Failures

### fsck Fails with "Cannot allocate memory"

**Error**:

```
fsck.ext2: Cannot allocate memory while trying to open /dev/hd0s2
```

**Cause**: Insufficient RAM allocated to QEMU

**Solution**:

```yaml
# Increase QEMU RAM in docker-compose.yml
environment:
  QEMU_RAM: 4096  # Increase to 4 GB or 8192 for 8 GB
```

**Rebuild and restart**:

```bash
docker-compose down
docker-compose build
docker-compose up -d
```

---

### fsck Reports "Too many errors"

**Error**:

```
fsck.ext2: Too many errors; aborting
```

**Cause**: Severe filesystem corruption

**Solutions**:

**1. Force fsck to continue**:

```bash
# Use -f (force) flag
/sbin/fsck.ext2 -f -y /dev/hd0s2
```

**2. Use more aggressive repair**:

```bash
# Try e2fsck with -p (auto-repair without prompts)
e2fsck -p /dev/hd0s2

# Or use -f -y together
e2fsck -f -y /dev/hd0s2
```

**3. Restore from backup**:

If filesystem is beyond repair, restore from backup:

```bash
# On host
cp debian-hurd-amd64-80gb.qcow2.backup debian-hurd-amd64-80gb.qcow2

# Or re-download fresh image
./scripts/setup-hurd-amd64.sh
```

---

### fsck Completes But System Still Won't Boot

**Symptom**: fsck reports "FILE SYSTEM WAS MODIFIED" but system still hangs or drops to emergency mode

**Causes**:
1. GRUB configuration damaged
2. Kernel panic
3. Init system failure

**Diagnostic**:

```bash
# At emergency prompt, check GRUB config
cat /boot/grub/grub.cfg | head -50

# Check kernel panic logs
dmesg | tail -50

# Check init system
systemctl status
```

**Solutions**:

**1. Reinstall GRUB** (if GRUB damaged):

```bash
# Mount root filesystem (if not mounted)
mount /dev/hd0s2 /mnt

# Reinstall GRUB
grub-install --boot-directory=/mnt/boot /dev/hd0

# Regenerate config
chroot /mnt
update-grub
exit

# Reboot
reboot
```

**2. Boot with different kernel** (if kernel panic):

At GRUB menu, select "Advanced options" and choose older kernel version.

**3. Restore from backup or re-provision**:

If all else fails, restore from working image or re-provision.

---

## Prevention Best Practices

### 1. Always Use Clean Shutdowns

```bash
# Inside guest
shutdown -h now

# Wait for "System halted" message

# Then stop QEMU
docker-compose down
```

### 2. Enable QCOW2 Image Snapshots

Create snapshots before major changes:

```bash
# Create snapshot (on host)
./scripts/manage-snapshots.sh create before-upgrade

# If something breaks, restore
./scripts/manage-snapshots.sh restore before-upgrade
```

### 3. Regular Backups

```bash
# Backup QCOW2 image
cp debian-hurd-amd64-80gb.qcow2 \
   debian-hurd-amd64-80gb.qcow2.backup-$(date +%Y%m%d)

# Compress for storage
tar czf debian-hurd-amd64-backup-$(date +%Y%m%d).tar.gz \
    debian-hurd-amd64-80gb.qcow2
```

### 4. Monitor QCOW2 Health

```bash
# Check image integrity regularly
qemu-img check debian-hurd-amd64-80gb.qcow2

# If errors found, repair immediately
qemu-img check -r all debian-hurd-amd64-80gb.qcow2
```

### 5. Add fsck Check to entrypoint.sh

```bash
#!/bin/bash

# Check QCOW2 before starting QEMU
if ! qemu-img check "$QCOW2_IMAGE" 2>&1 | grep -q "No errors"; then
    echo "[WARNING] QCOW2 image has errors, attempting repair..."
    qemu-img check -r all "$QCOW2_IMAGE"
fi

# Start QEMU
exec qemu-system-x86_64 ...
```

---

## Reference Commands

### Check QCOW2 Integrity (Host)

```bash
qemu-img check debian-hurd-amd64-80gb.qcow2
```

### Repair QCOW2 (Host)

```bash
qemu-img check -r all debian-hurd-amd64-80gb.qcow2
```

### Run fsck on Hurd Partition (Guest)

```bash
# Auto-repair
/sbin/fsck.ext2 -y /dev/hd0s2

# Or use generic fsck
/sbin/fsck -y /dev/hd0s2
```

### Force fsck on Next Boot (Guest)

```bash
# Inside guest, before shutdown
touch /forcefsck

# Next boot will run fsck automatically
shutdown -h now
```

### Check Filesystem Mount Status (Guest)

```bash
# List mounted filesystems
mount | grep -E "hd0|sd0"

# Check filesystem type
df -Th
```

---

## Recovery Checklist

When encountering fsck errors, follow this checklist:

- [ ] **Identify device**: Check error message for `/dev/hd0s2`, `/dev/sd0s2`, etc.
- [ ] **Run fsck with -y**: `/sbin/fsck.ext2 -y /dev/hd0s2`
- [ ] **Wait for completion**: fsck may take 1-5 minutes
- [ ] **Check for "MODIFIED" message**: Confirms repairs were made
- [ ] **Reboot**: `reboot` command
- [ ] **Verify clean boot**: System should boot without errors
- [ ] **If still failing**: Try fsck with `-f` (force)
- [ ] **If beyond repair**: Restore from backup or re-download image
- [ ] **Prevent future errors**: Always use clean shutdown procedures

---

## Additional Resources

- **ext2 filesystem documentation**: https://www.kernel.org/doc/html/latest/filesystems/ext2.html
- **e2fsck manual**: `man e2fsck` (inside GNU/Hurd guest)
- **QEMU image formats**: https://www.qemu.org/docs/master/system/images.html
- **GNU/Hurd filesystem guide**: https://www.gnu.org/software/hurd/hurd/translator/ext2fs.html

---

**Status**: Production Ready (x86_64-only)
**Last Updated**: 2025-11-07
**Architecture**: Pure x86_64
