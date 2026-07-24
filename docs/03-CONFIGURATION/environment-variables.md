# Environment Variables Reference

Complete reference of environment variables consumed by `entrypoint.sh` (container runtime) and helper scripts in `scripts/`.

## Resource Allocation

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `QEMU_RAM` | Integer (MB) | `4096` | Guest RAM in megabytes |
| `QEMU_SMP` | Integer | `2` | Virtual CPU count (cores) |
| `QEMU_MACHINE` | String | `pc` | QEMU machine type (pc, q35, microvm, etc.) |

**Examples**:
```bash
QEMU_RAM=8192 QEMU_SMP=4 make up      # 8GB RAM, 4 cores
QEMU_RAM=2048 QEMU_SMP=1 make up      # Minimal: 2GB RAM, 1 core
```

## Storage & Image

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `QEMU_DRIVE` | Path | `/opt/hurd-image/${HURD_IMAGE_BASENAME:-debian-hurd-amd64.qcow2}` | Guest disk image location in container |
| `HURD_IMAGE_BASENAME` | String | `debian-hurd-amd64.qcow2` | Select image filename from `./images` bind mount |
| `QEMU_CDROM` | Path | (empty) | Optional installer ISO path inside container (e.g. `/opt/hurd-installer/...iso`) |
| `QEMU_BOOT_ORDER` | String | (empty) | Optional boot order for QEMU (`c`, `d`, `dc`, etc.); auto-set to `d` when `QEMU_CDROM` is set |
| `QEMU_DISK_BUS` | String | `ide` | Disk controller type: `ide`, `ahci`, `scsi`, `nvme` |
| `QEMU_IDE_CONTROLLER` | String | `piix` | IDE controller model: `piix`, `ich9-ide`, `isa-ide` |
| `UNSAFE_CACHE` | Boolean | `0` | Use `cache=unsafe` for disk (⚠ data loss risk) |
| `AUTO_DOWNLOAD_IMAGE` | Boolean | `0` | Auto-download missing Debian GNU/Hurd image |
| `SKIP_CHECKSUM` | Boolean | `0` | Skip SHA256 verification during download |
| `IMAGE_TRACK` | String | `release` | Download track for `scripts/download-image.sh`: `release` (ports/13.0) or `latest` (ports/latest) |

**Examples**:
```bash
# Use AHCI controller (better performance on some systems)
QEMU_DISK_BUS=ahci make up

# Boot with the latest-image alias created by make setup-latest
HURD_IMAGE_BASENAME=debian-hurd-amd64.latest.qcow2 make up

# Boot fresh installer workflow disk with daily mini.iso
QEMU_CDROM=/opt/hurd-installer/debian-hurd-amd64-installer.latest-mini.iso \
QEMU_BOOT_ORDER=d HURD_IMAGE_BASENAME=debian-hurd-amd64.fresh.qcow2 make up

# Auto-download image if missing
AUTO_DOWNLOAD_IMAGE=1 make up

# Use unsafe cache (development only, not recommended)
UNSAFE_CACHE=1 make up
```

## I/O & Error Handling

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `QEMU_IDE_RERROR` | String | `auto` | IDE read error handling: `ignore`, `stop`, `report`, `auto` |
| `QEMU_IDE_WERROR` | String | `auto` | IDE write error handling: `ignore`, `stop`, `enospc`, `auto` |
| `QEMU_IDE_WRITE_CACHE` | String | `auto` | IDE write cache mode: `on`, `off`, `auto` |
| `QEMU_AHCI_BOUNCE_SIZE` | Integer | (empty) | AHCI DMA bounce buffer size (advanced) |
| `QEMU_PIIX_IDE_BOUNCE_SIZE` | Integer | (empty) | PIIX IDE DMA bounce buffer size (advanced) |
| `ENABLE_NATIVE_AIO` | Boolean | `0` | Enable native AIO (async I/O) for disk operations |

**Examples**:
```bash
# Strict I/O error handling (fail on errors)
QEMU_IDE_RERROR=stop QEMU_IDE_WERROR=stop make up

# Enable native AIO for better I/O performance
ENABLE_NATIVE_AIO=1 make up
```

## Acceleration & Performance

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `FORCE_KVM` | Boolean | `0` | Force KVM acceleration (fail if unavailable) |
| `DISABLE_KVM` | Boolean | `0` | Disable KVM, use TCG emulation |
| `AUTO_DISABLE_KVM_FOR_IDE` | Boolean | `1` | Automatically disable KVM if using IDE (avoids DMA errors) |
| `QEMU_NO_REBOOT` | Boolean | `0` | Add `-no-reboot` for one-shot debugging (default keeps VM alive across reboots) |
| `PRINT_QEMU_CMD` | Boolean | `0` | Print full QEMU command before starting |

**Examples**:
```bash
# Force KVM acceleration (will fail on non-KVM systems)
FORCE_KVM=1 make up

# Use TCG mode (slower, but works on all systems)
DISABLE_KVM=1 make up

# Debug: print QEMU command
PRINT_QEMU_CMD=1 make up

# One-shot mode: exit QEMU on guest reboot
QEMU_NO_REBOOT=1 make up

# Keep IDE with KVM (be aware of potential DMA issues)
AUTO_DISABLE_KVM_FOR_IDE=0 make up
```

## Display & Input/Output

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `ENABLE_VNC` | Boolean | `0` | Enable QEMU VNC output (port 5900) |
| `QEMU_VGA_DEVICE` | String | (empty) | VGA device: `std`, `virtio`, `qxl`, `vmware` |
| `SERIAL_PORT` | Integer | `5555` | Guest serial console telnet port on host |
| `MONITOR_PORT` | Integer | `9999` | QEMU monitor telnet port on host |
| `SSH_PORT` | Integer | `2222` | Guest SSH port on host (guest port 22 forwarded) |
| `HTTP_PORT` | Integer | `8080` | Guest HTTP port on host (guest port 80 forwarded) |

**Examples**:
```bash
# Enable VNC display (access via VNC client or VNC viewer)
ENABLE_VNC=1 make up

# Change serial console port
SERIAL_PORT=7777 make up

# Custom SSH port
SSH_PORT=2222 HTTP_PORT=8080 make up
```

## Network Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `QEMU_NET_MODEL` | String | (auto-detect) | Network device: `e1000`, `virtio`, `rtl8139` |
| `QEMU_HOSTFWDS` | String | `tcp::2222-:22,tcp::8080-:80` | Port forwarding rules (QEMU `-hostfwd` syntax) |
| `QEMU_SLIRP_NET` | String | (empty) | Slirp network configuration (advanced) |
| `QEMU_SLIRP_DHCPSTART` | String | (empty) | Slirp DHCP pool start IP (advanced) |

**Examples**:
```bash
# Use VirtIO network (better performance)
QEMU_NET_MODEL=virtio make up

# Custom port forwarding (also map port 3306 MySQL)
QEMU_HOSTFWDS=tcp::2222-:22,tcp::8080-:80,tcp::3306-:3306 make up

# Custom Slirp network configuration
QEMU_SLIRP_NET=10.0.2.0/24 QEMU_SLIRP_DHCPSTART=10.0.2.15 make up
```

## Server Control & Debugging

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `DISABLE_SERIAL` | Boolean | `0` | Disable serial telnet server |
| `DISABLE_MONITOR` | Boolean | `0` | Disable QEMU monitor telnet server |
| `HOST_SSH_PORT` | String | (empty) | Override host SSH port (internal use) |
| `HOST_HTTP_PORT` | String | (empty) | Override host HTTP port (internal use) |
| `HOST_SERIAL_PORT` | String | (empty) | Override host serial port (internal use) |
| `HOST_MONITOR_PORT` | String | (empty) | Override host monitor port (internal use) |

**Examples**:
```bash
# Disable serial console (for testing)
DISABLE_SERIAL=1 make up

# Disable QEMU monitor (for security/testing)
DISABLE_MONITOR=1 make up
```

## Advanced / Experimental

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `ENABLE_9P` | Boolean | `0` | Enable QEMU 9p filesystem share (experimental) |

**Note**: 9p filesystem sharing is experimental and may not work on all systems.

## Configuration Priority

Variables are resolved in this order (first match wins):

1. Explicit environment variable: `QEMU_RAM=8192 make up`
2. `.env` file in repo root: `QEMU_RAM=4096` in `.env`
3. Active Compose file set (`COMPOSE_FILE=...`): environment section(s)
4. `compose.yaml`: default values
5. Hardcoded defaults in `entrypoint.sh`

**Example Priority Chain**:
```bash
# 1. Command-line (highest priority)
QEMU_RAM=8192 make up

# 2. .env file (if no command-line override)
cat > .env << EOF
QEMU_RAM=4096
QEMU_SMP=2
EOF
make up

# 3. compose override file in COMPOSE_FILE chain
cat > compose.local.yaml << EOF
services:
  gnu-hurd-dev:
    environment:
      QEMU_RAM: "4096"
      QEMU_SMP: "2"
EOF
COMPOSE_FILE=compose.yaml:compose.bind.yaml:compose.local.yaml make up

# 4. compose.yaml defaults are used as fallback
```

## Common Combinations

### Minimal Setup (Testing/Learning)
```bash
QEMU_RAM=2048 QEMU_SMP=1 DISABLE_KVM=1 make up
```

### Recommended Development
```bash
QEMU_RAM=4096 QEMU_SMP=2 make up-kvm
```

### Performance Testing
```bash
QEMU_RAM=8192 QEMU_SMP=4 ENABLE_NATIVE_AIO=1 QEMU_DISK_BUS=ahci make up-kvm
```

### Debugging with All Output
```bash
PRINT_QEMU_CMD=1 ENABLE_VNC=1 ENABLE_NATIVE_AIO=1 make up
```

### Rootless Podman
```bash
# Most settings work the same through the orchestration wrapper
CONTAINER_RUNTIME=podman QEMU_RAM=4096 QEMU_SMP=2 make up
```

## Verification

To verify environment variable settings inside the running container:

```bash
# View current QEMU settings
docker exec gnu-hurd-dev env | grep QEMU

# Check actual QEMU process arguments
docker exec gnu-hurd-dev ps aux | grep qemu-system

# Check guest resource allocation
docker exec gnu-hurd-dev nproc          # CPU cores
docker exec gnu-hurd-dev free -h        # RAM
docker exec gnu-hurd-dev df -h /        # Disk space
```

## Variables that are not read

Documentation and older reports name several variables that `entrypoint.sh` never
reads. Setting them has no effect, which is worse than an unknown option because a
reader concludes the setting was tried and did not help. Each maps to the variable
that carries the same intent, where one exists.

| Named in older docs | Actually read | Notes |
| --- | --- | --- |
| `QEMU_STORAGE` | `QEMU_DISK_BUS` | Values are `ide`, `ahci`, `scsi`. The old `sata` corresponds to `ahci`. |
| `QEMU_VIDEO` | `QEMU_VGA_DEVICE` | Passed through to `-device`. |
| `QEMU_AIO` | `ENABLE_NATIVE_AIO` | Boolean, not an AIO backend name. |
| `QEMU_ACCEL` | `DISABLE_KVM`, `FORCE_KVM`, `AUTO_DISABLE_KVM_FOR_IDE` | Acceleration is selected by these booleans rather than by a QEMU flag string. |
| `QEMU_EXTRA_ARGS` | none | No passthrough for arbitrary QEMU arguments. Machine type is `QEMU_MACHINE`. |
| `QEMU_CPU` | none | The CPU model is not configurable through the entrypoint. |
| `QEMU_ARCH` | none | The image is x86_64 only; i386 was retired 2025-11-07. |
| `QEMU_NIC` | `QEMU_NET_MODEL` | Selects the network device model. |
| `QEMU_FSCK` | none | The guest runs `fsck` from its own boot scripts. Repair the filesystem offline with `scripts/guestfish-check-guest-filesystem.sh`. |
| `QEMU_DISK_SIZE` | none | Disk size is a property of the qcow2, changed with `qemu-img resize`. |
| `QEMU_MONITOR` | `MONITOR_PORT`, `DISABLE_MONITOR` | The monitor is exposed over TCP rather than a socket path. |
| `QEMU_LOG` | none | The guest-error log path is fixed at `/tmp/qemu-guest-errors.log` inside the container. |

To list candidate names while auditing this table:

```sh
grep -oP '\$\{\K[A-Z][A-Z0-9_]*' entrypoint.sh | sort -u
```

This is a discovery aid rather than a generated contract. It matches only braced
`${NAME}` expansions, so it misses bare `$NAME` reads, and it cannot separate
externally supplied configuration from variables the script sets for itself.
Treat its output as a list to check by hand. Making this reference generated and
enforceable needs an explicit configuration schema that `entrypoint.sh` and this
document both derive from.

## References

- [RESOURCE-SIZING.md](RESOURCE-SIZING.md) - Detailed resource allocation guidance
- [entrypoint.sh](https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker/blob/main/entrypoint.sh) - Source of truth for variable usage
- [compose.yaml](https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker/blob/main/compose.yaml) - Default values
- [OPTIMIZATION-2025.md](../02-ARCHITECTURE/qemu/OPTIMIZATION-2025.md) - Performance tuning

---

*Last updated: 2026-01-14*
*Complete reference for all supported environment variables*
