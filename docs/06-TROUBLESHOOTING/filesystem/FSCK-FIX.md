# Fixing fsck Error on GNU/Hurd

**Error:** `unexpected inconsistency; RUN fsck MANUALLY` on `/dev/hd0s2`

---

## What This Means

The Hurd filesystem (/dev/hd0s2) has inconsistencies, likely because:
1. QCOW2 image wasn't shut down cleanly previously
2. Filesystem corruption from abrupt QEMU termination
3. First boot filesystem check

This is **normal and fixable** - just requires manual intervention.

---

## Solution 1: Interactive fsck (Recommended)

### In the QEMU window:

When you see the fsck error, you'll be dropped to a prompt.

**Type these commands:**

```bash
# Run filesystem check
/sbin/fsck.ext2 -y /dev/hd0s2

# Or if that doesn't work:
/sbin/fsck -y /dev/hd0s2

# Then reboot
reboot
```

The `-y` flag answers "yes" to all repair prompts automatically.

### Alternative: Manual Repair

If you get an interactive fsck prompt asking questions:

```
Fix <problem>? yes
```

Just type `yes` or `y` and press Enter for each prompt.

After all repairs, the system should continue booting.

---

## Solution 2: Boot to Single User Mode

If filesystem won't mount:

1. **At GRUB menu**, press `e` to edit boot entry
2. **Add to kernel line:** `single` or `1`
3. **Press Ctrl+X** to boot
4. **Run fsck manually:**
   ```bash
   /sbin/fsck.ext2 -y /dev/hd0s2
   reboot
   ```

---

## Solution 3: Fix from Host (Before Boot)

If QEMU won't boot at all, fix the QCOW2 from host:

```bash
# Stop QEMU if running
pkill qemu-system-i386

# Check QCOW2 integrity
qemu-img check debian-hurd-i386-20250807.qcow2

# If corruption detected, try to repair:
qemu-img check -r all debian-hurd-i386-20250807.qcow2

# If that fails, restore from backup or re-download
cp debian-hurd-i386-20250807.qcow2 debian-hurd-i386-20250807.qcow2.backup
# Then re-download original image
```

---

## Prevention: Always Shut Down Cleanly

### Proper Shutdown

**Inside Hurd:**
```bash
shutdown -h now
# Wait for "System halted" message
```

**Then in QEMU monitor:**
```
quit
```

### Emergency: If Hurd is Unresponsive

**In QEMU monitor (stdio terminal):**
```
system_powerdown
# Wait 10 seconds
quit
```

**Never just kill QEMU process** - this causes filesystem corruption!

---

## What to Expect After Repair

1. fsck will fix errors (may take 1-5 minutes)
2. System will either:
   - Continue booting automatically
   - Prompt you to reboot
   - Drop to single-user shell

3. If dropped to shell:
   ```bash
   reboot
   ```

4. Next boot should be clean

---

## Current Situation - Quick Steps

**Right now in your QEMU window:**

1. **Look for a prompt** (might be `(Repair filesystem) 1 #` or similar)
2. **Type:**
   ```bash
   /sbin/fsck.ext2 -y /dev/hd0s2
   ```
3. **Press Enter**
4. **Wait for fsck to complete** (watch for "FILE SYSTEM WAS MODIFIED")
5. **Type:**
   ```bash
   reboot
   ```
6. **System should boot cleanly now**

---

## Alternative: Fresh Start

If fsck fails repeatedly:

```bash
# Stop QEMU
pkill qemu-system-i386

# Download fresh image
cd /home/eirikr/Playground/gnu-hurd-docker
./scripts/download-image.sh

# This will overwrite the corrupted QCOW2
# Then restart QEMU
```

---

## For Docker: Prevent This Issue

Add to entrypoint.sh to handle unclean shutdowns:

```bash
# Check QCOW2 before starting
if ! qemu-img check "$QCOW2_IMAGE" 2>&1 | grep -q "No errors"; then
    echo "[WARNING] QCOW2 image has errors, attempting repair..."
    qemu-img check -r all "$QCOW2_IMAGE"
fi
```

---

**Status:** Filesystem error detected - repair needed
**Action:** Run fsck manually in QEMU window
**Time:** 1-5 minutes to repair
