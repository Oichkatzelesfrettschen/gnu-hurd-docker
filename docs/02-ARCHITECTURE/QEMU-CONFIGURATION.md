# QEMU Configuration

This project runs a Debian GNU/Hurd **x86_64 guest** under QEMU inside the `gnu-hurd-dev` container. Configuration is primarily controlled via environment variables passed through Compose.

If you need the previous, long-form QEMU configuration document (including historical tuning notes and legacy naming), see `docs/02-ARCHITECTURE/archive/QEMU-CONFIGURATION-LEGACY.md`.

## Key paths

- Guest disk (container): `QEMU_DRIVE=/opt/hurd-image/debian-hurd-amd64.qcow2`
- Guest disk (bind mode on host): `./images/debian-hurd-amd64.qcow2`

## Key environment variables

These are set in `docker-compose.yml` and read by `entrypoint.sh`:

- `QEMU_DRIVE`: path to the QCOW2 inside the container
- `QEMU_RAM`: RAM in MB (default in compose: `4096`)
- `QEMU_SMP`: vCPU count (default in compose: `2`)
- `ENABLE_VNC`: `1` enables VNC; `0` disables
- `SERIAL_PORT`: host/container port for the serial telnet server (default: `5555`)
- `MONITOR_PORT`: host/container port for the QEMU monitor telnet server (default: `9999`)
- `DISABLE_SERIAL`: set to `1` to disable the serial telnet server
- `DISABLE_MONITOR`: set to `1` to disable the QEMU monitor telnet server

## Acceleration model

- On Linux `x86_64` hosts with `/dev/kvm`, KVM is used when available.
- On other hosts (including `arm64`), QEMU uses TCG (software emulation).
- You can explicitly disable KVM by setting `DISABLE_KVM=1` in the container environment.

## Where the truth lives

- Compose defaults: `docker-compose.yml`
- Runtime logic: `entrypoint.sh`
- Standalone (no container): `scripts/run-hurd-qemu.sh`
