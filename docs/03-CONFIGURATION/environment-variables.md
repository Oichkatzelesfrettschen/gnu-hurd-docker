# Environment Variables (Canonical)

Environment variables are consumed by `entrypoint.sh` (container runtime) and the helper scripts in `scripts/`.

## Core QEMU settings

- `QEMU_DRIVE`: path to QCOW2 inside container (default: `/opt/hurd-image/debian-hurd-amd64.qcow2`)
- `QEMU_RAM`: guest RAM in MB (default: `4096` via `docker-compose.yml`)
- `QEMU_SMP`: vCPU count (default: `2` via `docker-compose.yml`)
- `ENABLE_VNC`: `1` to enable QEMU VNC output on port 5900 (default `0`)
- `SERIAL_PORT`: serial console telnet port (default `5555`)
- `MONITOR_PORT`: QEMU monitor telnet port (default `9999`)
- `DISABLE_SERIAL`: `1` to disable the serial telnet server (default `0`)
- `DISABLE_MONITOR`: `1` to disable the QEMU monitor telnet server (default `0`)
- `QEMU_HOSTFWDS`: comma-separated QEMU hostfwd rules (default: `tcp::2222-:22,tcp::8080-:80`)

## Disk/image helpers

- `AUTO_DOWNLOAD_IMAGE`: `1` to download and prepare the image inside the container when missing (default `0`)
- `SKIP_CHECKSUM`: `1` to skip `SHA256SUMS` verification when using `scripts/download-image.sh` (default `0`)

## Experimental

- `ENABLE_9P`: `1` to add a QEMU 9p share for `/share` (mount tag `hostshare`) (default `0`)
- `UNSAFE_CACHE`: `1` to use QEMU `cache=unsafe` for the disk (risk of data loss) (default `0`)
