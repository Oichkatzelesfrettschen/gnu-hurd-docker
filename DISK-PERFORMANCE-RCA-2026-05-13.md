# Hurd guest disk I/O performance RCA

**Symptom**: apt-get upgrade takes 40+ minutes on a guest with otherwise
quiet host (CPU 60%, RAM 1.9 GB, host NVMe at <1% utilization).

## Root cause: TCG software emulation, not KVM

The `gnu-hurd-docker` entrypoint contains an explicit
`AUTO_DISABLE_KVM_FOR_IDE` guard
(`entrypoint.sh:298-307`):

```sh
# Known issue: KVM + PIIX IDE can trigger repeated "bus-master DMA error:
# missing interrupt" and ext2fs I/O errors.
# Prefer reliability over speed by auto-disabling KVM for IDE on pc/i440fx,
# unless the user explicitly overrides it.
if [ "$accel_mode" = "kvm" ] && [ "${AUTO_DISABLE_KVM_FOR_IDE:-1}" = "1" ] && [ "${FORCE_KVM:-0}" != "1" ]; then
    case "${QEMU_MACHINE}" in
        pc*)
            if [ "$disk_bus_hint" = "ide" ]; then
                accel_mode="tcg"
                log_warn "Auto-disabling KVM: detected KVM + IDE on '${QEMU_MACHINE}' (set FORCE_KVM=1 to override)"
            fi
            ;;
    esac
fi
```

This means the running cmdline shows:
```
-accel tcg,thread=multi -cpu max -m 2048 -smp 2
```

instead of the expected
```
-accel kvm -cpu host -m 2048 -smp 2
```

TCG (Tiny Code Generator) is a *software* x86_64 emulator inside QEMU;
each guest instruction is dynamically translated to host code.  Expect
**5-50x slower** than KVM for compute-heavy workloads.  For apt's
dpkg-configure scripts that fork+exec many shell commands, the
overhead compounds.

## Verifying with host I/O baseline

While the guest was in dpkg-configure, host iotop showed:
```
qemu-system-x86_64 ... 241.23 K/s writes
```

The qcow2 lives on `/dev/nvme1n1p2` (ext4, `noatime,commit=60`), which
is capable of 100s of MB/s of random writes.  The host hardware is
*not* the bottleneck.

## Options

### Option A: FORCE_KVM=1 (fast, risk DMA issue resurfacing)

Restart container with:
```sh
podman run -d --rm --name hurd-fix \
    --device /dev/kvm \
    -e FORCE_KVM=1 \
    -e QEMU_SMP=2 -e QEMU_RAM=2048 \
    ...
```

This bypasses the guard.  Risk: if the documented "bus-master DMA
error / ext2fs I/O error" reproduces, the fs becomes dirty and we have
to e2fsck on the host.  We've already seen that error pattern earlier
in this session when we let `QEMU_SMP` auto-scale to 6 CPUs.  With
`SMP=2` it may not trigger -- worth testing.

### Option B: switch machine type to q35 + SATA/AHCI

q35 has a different chipset (ICH9) that exposes SATA via AHCI instead
of PIIX IDE.  KVM + AHCI may be more reliable on Hurd, and AHCI's
NCQ is much faster than legacy IDE PIO mode 4.

```sh
podman run -d --rm \
    -e QEMU_MACHINE=q35 \
    -e QEMU_DISK_BUS=ahci \
    -e FORCE_KVM=1 \
    ...
```

Hurd's `rumpdisk` translator supports AHCI/SATA per the Debian Hurd
notes, so this *should* work.  Risk: grub.cfg references
`root=part:5:device:wd0` which is the IDE/PIIX device name.  Switching
the bus changes the device name (sd0 for SCSI; AHCI is still wd0 but
the controller is different).  Would need to re-test.

### Option C: cache=unsafe (dev-only, host RAM acts as full WB cache)

```sh
podman run -d --rm \
    -e QEMU_DISK_CACHE=unsafe \
    ...
```

Disables flush-to-disk for *guest* writes.  Host crash = guest data
loss, but interactive performance is much closer to native.  For a
dev/throwaway VM this is fine; the entrypoint already supports it via
`QEMU_DISK_CACHE=unsafe`.

### Option D: Tmpfs overlay for /var/cache/apt + /tmp inside guest

Mount `/var/cache/apt/archives` and `/tmp` as tmpfs inside Hurd so
dpkg doesn't write to ext2fs translator for transient files.  Hurd
supports tmpfs via `/hurd/tmpfs`.  Less invasive than changing
machine, helps apt specifically.

## Recommended next action

Try **Option C** (cache=unsafe) first -- it's a single env var, doesn't
touch the chipset, and gets ~10x speedup for write-heavy workloads
without changing guest fs.  If still slow, try **A** (FORCE_KVM) with
SMP=2 + cache=unsafe combined.

## Followups

* Verify Hurd actually has virtio-blk support in 0.9.git20251029 --
  some recent Hurd builds added rumpdisk virtio backend.  If yes,
  `QEMU_DISK_BUS=virtio` would be the fastest option.
* File an issue against `gnu-hurd-docker` to document the
  TCG-vs-KVM tradeoff more visibly in the README (currently it's a
  buried `log_warn` line, easy to miss).
