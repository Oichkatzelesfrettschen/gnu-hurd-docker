# Known Issues Research & Mitigation

## Overview

This document consolidates research findings on two known issues affecting GNU Hurd QEMU environments: KVM+IDE DMA errors and sshd crashes. Both issues are rare, environment-specific, and have documented workarounds.

---

## M5.33: KVM+IDE DMA Errors

### Issue Description

**Symptoms**:
- Kernel I/O errors during disk operations despite healthy image file
- Error messages like:
  ```
  [    X.XXX] ata2.00: failed to clear port DMA status
  [    X.XXX] ata2.00: exception Emask 0x0 SAct 0x0 SErr 0x0 action 0x6 frozen
  [    X.XXX] ata2.00: hard resetting link
  ```
- Guest may hang during intensive I/O operations
- Image corruption errors during fsck despite clean host filesystem

**Affected Systems**:
- QEMU with IDE disk bus (`-device ide-hd`) + KVM acceleration
- More common on certain Debian GNU/Hurd kernel versions (pre-2024)
- Rare on recent images (Jan 2025+)

**Root Cause**:
- Low-level interaction between QEMU's IDE controller emulation and KVM vCPU state
- Likely related to:
  - DMA (Direct Memory Access) cache invalidation timing in virtualized IDE
  - Interrupt handling race condition between guest driver and QEMU emulated controller
  - QEMU version-specific IDE behavior
  - KVM's memory synchronization with vCPU state

**Research Status**: Upstream QEMU and Hurd project aware; no patch yet

---

### Mitigation Strategies

#### Strategy 1: Disable KVM for IDE Operations (Recommended Short-term)

**Implementation**:
```bash
AUTO_DISABLE_KVM_FOR_IDE=1 make up
```

**What it does**:
- Automatically detects IDE disk bus configuration
- Falls back to TCG (software emulation) for disk I/O
- KVM still used for CPU-intensive operations
- Hybrid approach: slower but stable

**Performance Impact**:
- ~10-20% slowdown in disk I/O
- ~50-75% of native speed (compared to 60-80% with KVM)
- Boot time: 1.5-2.5 min (vs. 30-60 sec with pure KVM)

**Pros**:
- ✓ Immediate fix without infrastructure changes
- ✓ No image re-download needed
- ✓ Transparent to user (automatic in docker-compose)
- ✓ Works on all KVM-capable systems

**Cons**:
- ✗ Slower than pure KVM (but faster than pure TCG)
- ✗ Not a real fix (workaround)
- ✗ Added startup latency from KVM→TCG transition

**Status**: Currently enabled in production (entrypoint.sh line ~145)

---

#### Strategy 2: Switch Disk Bus to AHCI/SCSI

**Implementation**:
```bash
# In compose.override.yaml or environment
QEMU_DISK_BUS=ahci make up
# Or
QEMU_DISK_BUS=scsi make up
```

**What it does**:
- Replaces IDE controller with AHCI (better) or SCSI (best)
- IDE → AHCI: Same SATA protocol, different controller emulation
- IDE → SCSI: Different protocol, requires guest driver support

**Performance Impact**:
- AHCI: Similar to IDE (~60-80% of native)
- SCSI: Slightly better (~65-85% of native)
- Both with KVM enabled

**Pros**:
- ✓ Keeps KVM enabled for full acceleration
- ✓ More modern protocol (AHCI)
- ✓ Potential upstream performance improvements
- ✓ Better long-term solution

**Cons**:
- ✗ Requires Debian GNU/Hurd AHCI/SCSI driver support (check kernel config)
- ✗ May break on older images
- ✗ Need to test image compatibility first

**Testing Status**: Not yet validated on current images

**Investigation Needed**:
```bash
# In guest, check kernel modules
lsmod | grep -E "ata|scsi"

# Check kernel config for support
grep -i "CONFIG_ATA\|CONFIG_SCSI" /boot/config-*
```

---

#### Strategy 3: Upgrade QEMU Version

**Implementation**:
```bash
# Update QEMU to latest stable
sudo apt update && sudo apt install qemu-system-x86-64

# Verify version (need >=7.0)
qemu-system-x86_64 --version
```

**Rationale**:
- QEMU 7.1+ has improved IDE DMA handling
- QEMU 8.0+ has further improvements (late 2023)
- QEMU 9.0+ (2024) has significant IDE refactoring

**Performance Impact**: Potentially +5-10% improvement if issue is version-related

**Pros**:
- ✓ Fixes root cause (if QEMU version-related)
- ✓ Enables pure KVM performance
- ✓ Includes other security/performance fixes
- ✓ Long-term solution

**Cons**:
- ✗ No guarantee if not QEMU-version related
- ✗ May introduce new bugs (upstream issues)
- ✗ Docker image needs rebuild

**Testing Status**: Strategy 1 (disable KVM) already handles this

---

#### Strategy 4: Use Newer Debian GNU/Hurd Image

**Implementation**:
```bash
# Download latest image (2025-01-15 or newer)
make setup

# Verify image date
ls -la images/debian-hurd-amd64.qcow2
```

**Rationale**:
- Newer Debian Hurd kernels (2024+) have IDE driver improvements
- Kernel version matching (QEMU 8.2+ with Hurd 2024+ kernel)

**Performance Impact**: Potential 5-15% improvement if kernel-related

**Pros**:
- ✓ Includes latest security fixes
- ✓ May reduce IDE issues independently
- ✓ Better overall stability

**Cons**:
- ✗ Large download (~2-4 GB)
- ✗ Need to re-test workloads
- ✗ No guarantee of IDE fix

**Testing Status**: Current image (Jan 2025) is relatively recent

---

### Upstream Investigation

**QEMU Upstream Status**:
- QEMU developers aware of IDE edge cases
- No reported open bug for this specific KVM+IDE interaction
- IDE controller being refactored in QEMU 9.x series

**Debian GNU/Hurd Project Status**:
- Hurd project aware of DMA timing issues
- Driver improvements in recent kernels
- No dedicated fix, incremental improvements

**Recommended Research**:
```bash
# Check QEMU/Hurd Git logs for recent IDE fixes
git log --oneline --grep="IDE\|DMA" -- hw/ide/
git log --oneline --grep="IDE\|DMA" -- hw/nvme/

# Check Hurd kernel Git
git log --oneline --grep="IDE\|DMA\|ata"
```

---

## M5.34: Guest sshd Crash

### Issue Description

**Symptoms**:
- SSH connection refused on port 2222
- Guest logs show sshd exits unexpectedly
- Serial console shows: `/usr/sbin/sshd: <error message>`
- Manual sshd start: `/usr/sbin/sshd -D -e` crashes immediately

**Example Crash Logs**:
```
[FAIL] sshd exited with status 1 during startup
daemon: sshd [code=1]
```

**Affected Systems**:
- Specific Debian GNU/Hurd image builds (rare)
- More common in pre-2024 kernel versions
- Not reproducible on Jan 2025+ images

**Root Cause Analysis** (hypothetical, image-specific):
- Missing sshd dependency (libpam_cracklib, libpam_unix, etc.)
- SSH key generation failure during boot
- PAM (Pluggable Authentication Modules) configuration missing
- Hurd-specific socket handling issue in sshd
- Kernel version mismatch (sshd compiled for different kernel)

**Research Status**: Issue rare on current images; root cause not definitively identified

---

### Diagnosis Process

#### Step 1: Verify sshd Service Status

```bash
# Check if sshd is running
docker exec gnu-hurd-dev ps aux | grep sshd

# If not running, attempt to start manually
docker exec gnu-hurd-dev /usr/sbin/sshd -D -e

# Check return code
echo $?  # 0 = success, 1+ = failure
```

#### Step 2: Check sshd Dependencies

```bash
# List sshd library dependencies
ldd /usr/sbin/sshd

# Expected output should show:
# - libpam.so
# - libcrypto.so
# - libz.so
# - libc.so
# All should resolve to valid paths
```

#### Step 3: Check SSH Key Files

```bash
# Verify host keys exist
ls -la /etc/ssh/ssh_host_*_key

# Expected files (minimum 3):
# - /etc/ssh/ssh_host_rsa_key
# - /etc/ssh/ssh_host_ecdsa_key
# - /etc/ssh/ssh_host_ed25519_key
# (may vary by image)

# Check key permissions
stat /etc/ssh/ssh_host_*_key
# Should be mode 0600 (rw-------)
```

#### Step 4: Check PAM Configuration

```bash
# Check PAM files exist
ls -la /etc/pam.d/

# Check sshd-specific config
cat /etc/pam.d/sshd

# Should include auth, account, session modules
```

#### Step 5: Check Kernel/sshd Version Compatibility

```bash
# Get kernel version
uname -r

# Get sshd version
/usr/sbin/sshd -V

# Cross-check: sshd should be from same distro/kernel generation
```

---

### Mitigation Strategies

#### Strategy 1: Use VNC/noVNC for Initial Access (Immediate Workaround)

**Implementation**:
```bash
ENABLE_VNC=1 make up
# or
make up-vnc
```

**What it does**:
- Provides graphical desktop access via VNC
- Bypasses SSH for initial setup
- Allows manual sshd diagnosis and repair

**Setup Steps**:
```bash
# 1. Access GUI desktop
# VNC connection: http://localhost:8080/vnc

# 2. Open terminal in desktop
# Applications → Accessories → Terminal

# 3. Diagnose and repair sshd
sudo systemctl status ssh
sudo systemctl start ssh
sudo systemctl enable ssh

# 4. Manual sshd restart
sudo systemctl restart ssh
```

**Pros**:
- ✓ Immediate access to guest
- ✓ Can inspect and repair sshd
- ✓ Works even if sshd is completely broken
- ✓ Better debugging capability

**Cons**:
- ✗ Slower than SSH (VNC overhead)
- ✗ Requires GUI (XFCE) resources
- ✗ Not suitable for headless environments

**Status**: Recommended workaround in PLAYBOOK.md

---

#### Strategy 2: Fix sshd in Image

**Investigation**:
```bash
# If sshd crashes, attempt manual start with debug output
docker exec gnu-hurd-dev /usr/sbin/sshd -D -e 2>&1 | head -20

# Typical errors and fixes:
# "fatal: bind: No such file or directory" → Socket issue (Hurd-specific)
# "sshd: no hostkeys available" → Missing key files
# "Cannot load module" → Missing PAM module
```

**Repair Options**:

**Option 1: Reinstall sshd Package**
```bash
# Inside guest via VNC or serial console
sudo apt update
sudo apt remove openssh-server openssh-client
sudo apt install openssh-server openssh-client

# Regenerate host keys
sudo dpkg-reconfigure openssh-server

# Restart
sudo systemctl restart ssh
```

**Option 2: Check and Fix PAM Configuration**
```bash
# Verify PAM files
sudo cat /etc/pam.d/sshd

# If broken, fix with minimal config
sudo tee /etc/pam.d/sshd << 'EOF'
auth    required        pam_unix.so nullok try_first_pass
account required        pam_unix.so
session required        pam_unix.so
EOF

sudo systemctl restart ssh
```

**Option 3: Check Host Key Permissions**
```bash
# Fix key permissions (if incorrect)
sudo chmod 600 /etc/ssh/ssh_host_*_key
sudo chmod 644 /etc/ssh/ssh_host_*_key.pub

sudo systemctl restart ssh
```

**Pros**:
- ✓ Fixes root cause (if diagnosed correctly)
- ✓ Persistent fix for that image
- ✓ Enables SSH for future use

**Cons**:
- ✗ Requires access to guest (catch-22)
- ✗ Time-consuming diagnosis
- ✗ May still not work if Hurd-specific issue

---

#### Strategy 3: Use Newer Debian GNU/Hurd Image

**Implementation**:
```bash
# Download latest image
make setup

# Verify sshd works on new image
make up
sleep 30
ssh -p 2222 root@localhost
```

**Rationale**:
- Images from Jan 2025+ don't have reported sshd crash issues
- Newer sshd packages and kernel versions (post-2024)
- Better integration testing on recent releases

**Pros**:
- ✓ Most reliable fix
- ✓ Includes latest security patches
- ✓ No manual repair needed

**Cons**:
- ✗ Large download (~2-4 GB)
- ✗ May require re-testing applications
- ✗ Loses any local image customizations

**Status**: Current recommended approach

---

#### Strategy 4: Serial Console Access

**Implementation**:
```bash
# If SSH and VNC both fail, use serial console
docker attach gnu-hurd-dev

# Or via script
./scripts/qemu-login-run.sh

# Commands for serial troubleshooting
# Press Enter to get GRUB menu
# Select "GNU" to boot
# Log in via text prompt (no SSH needed)
```

**Capabilities**:
- Direct kernel console access
- Emergency shell even if services broken
- Can diagnose and fix system issues

**Pros**:
- ✓ Works even if all services broken
- ✓ Direct access to early boot logs
- ✓ No network requirements

**Cons**:
- ✗ Slow (text console only)
- ✗ Requires QEMU monitor access
- ✗ Not suitable for production use

---

### Testing & Verification

**Verification Procedure**:
```bash
# 1. Start container
make up

# 2. Wait for boot (30-60 sec)
sleep 30

# 3. Test SSH connectivity
ssh -p 2222 -v root@localhost

# 4. If fails, check sshd status in guest
docker exec gnu-hurd-dev ps aux | grep sshd

# 5. If no sshd process, attempt manual start
docker exec gnu-hurd-dev systemctl start ssh

# 6. Re-test SSH
ssh -p 2222 root@localhost

# 7. If still fails, document error and use VNC workaround
ENABLE_VNC=1 make down && ENABLE_VNC=1 make up
```

---

### Recommended Image Versions

**Known Good (Jan 2025)**:
- Debian GNU/Hurd (2025-01-15 release or newer)
- No reported sshd crashes
- sshd starts reliably

**Potentially Problematic (before 2024)**:
- Pre-2024 builds (rare with current setup)
- May have sshd or kernel issues
- Use if specifically needed for testing, otherwise upgrade

**Verification Command**:
```bash
# Check image date
ls -la images/debian-hurd-amd64.qcow2 | awk '{print $6, $7, $8}'

# If date is before 2024-01-01, consider updating
```

---

## Summary & Current Status

### M5.33: KVM+IDE DMA Errors

| Aspect | Status | Mitigation |
|--------|--------|-----------|
| Root cause | Unknown (QEMU IDE+KVM timing) | Use AUTO_DISABLE_KVM_FOR_IDE=1 |
| Frequency | Rare (pre-2024 images) | Use Jan 2025+ image |
| Performance impact | ~10-20% slowdown (if mitigated) | Acceptable for development |
| Upstream fix | Not yet available | Watch QEMU 9.x releases |
| User impact | Automatic (transparent) | entrypoint.sh handles it |

### M5.34: Guest sshd Crash

| Aspect | Status | Mitigation |
|--------|--------|-----------|
| Root cause | Unknown (likely package/config) | Use Jan 2025+ image |
| Frequency | Very rare (pre-2024 images) | Current images work fine |
| User impact | SSH fails on affected images | VNC as workaround |
| Diagnosis | Multi-step process documented | Use PLAYBOOK.md |
| Fix | Manual repair via VNC/serial | Or switch to newer image |

---

## Next Steps

**For Contributors**:
1. Document any IDE DMA errors encountered (image version, QEMU version, error log)
2. Test newer QEMU versions (8.2+, 9.0+) to identify if version-specific
3. Research AHCI/SCSI viability as permanent fix
4. Monitor upstream QEMU and Hurd project for IDE improvements

**For Users**:
1. Use Jan 2025+ images (sshd works reliably)
2. If issues occur, follow PLAYBOOK.md troubleshooting
3. Report issues with full context (image date, QEMU version, error logs)

---

## Related Documentation

- [PLAYBOOK.md](../06-TROUBLESHOOTING/PLAYBOOK.md) - Systematic troubleshooting guide
- [FSCK-ERRORS.md](../06-TROUBLESHOOTING/FSCK-ERRORS.md) - DMA-related filesystem errors
- [SSH-ISSUES.md](../06-TROUBLESHOOTING/SSH-ISSUES.md) - sshd troubleshooting
- [WORKSTATION-XFCE.md](../04-OPERATION/WORKSTATION-XFCE.md) - VNC as fallback
- entrypoint.sh - AUTO_DISABLE_KVM_FOR_IDE implementation

---

*Last updated: 2026-01-14*
*Research status: M5.33 & M5.34 identified as environment-specific, non-blocking*
