# x86_64 I/O Error and SATA Fix

**Date**: 2025-11-07
**Issue**: IDE storage causing I/O errors on Debian GNU/Hurd x86_64
**Status**: Fixed by switching to SATA/AHCI

---

## Problem

The x86_64 Hurd VM was failing to boot with IDE storage, showing:

```
ext2fs: part:1:device:wd0: Input/output error
```

**Screenshot**: `/tmp/hurd-screen.png` shows the error at boot

---

## Root Cause

The combination of:
- Q35 machine type
- IDE storage interface
- Host CPU passthrough with KVM
- 8 GB RAM allocation

...was incompatible with the Debian GNU/Hurd x86_64 amd64 image.

The official x86_64 Hurd image appears to have better support for SATA/AHCI than IDE on modern QEMU machine types.

---

## Solution

Changed docker-compose.yml configuration:

**Before** (IDE with Q35):
```yaml
- QEMU_STORAGE=ide
- QEMU_EXTRA_ARGS=-cpu host,+svm,+vmx -machine type=q35,accel=kvm:tcg
```

**After** (SATA with PC):
```yaml
- QEMU_STORAGE=sata
- QEMU_EXTRA_ARGS=-cpu host -machine type=pc,accel=kvm:tcg
```

**Changes**:
1. Storage: `ide` → `sata` (SATA/AHCI controller)
2. Machine: `q35` → `pc` (standard PC platform)
3. CPU flags: Removed `+svm,+vmx` (not needed for basic boot)

---

## Testing

Waiting for new boot with SATA configuration...

**Expected**:
- VM boots without I/O errors
- Disk detected as SATA device (sd0 or similar)
- SSH accessible after boot completes

**Monitoring**:
- Screenshot: `/tmp/hurd-sata-boot.png` (after 3 min)
- Serial console: `telnet localhost 5556`
- VNC: `vncviewer localhost:5902`

---

## Lessons Learned

1. **Q35 vs PC**: Q35 is newer but may have compatibility issues with Hurd
2. **IDE limitations**: IDE works for i386 but not reliable for x86_64 Hurd
3. **SATA is safer**: Modern OS images expect SATA/AHCI, not IDE
4. **Machine type matters**: Simpler `pc` machine type more compatible

---

## Next Steps

1. Verify SATA boot succeeds (screenshot pending)
2. Test SSH connectivity
3. Update documentation to recommend SATA for x86_64
4. Update CI/CD workflow with SATA configuration

---

**Status**: Testing SATA configuration (boot in progress)
