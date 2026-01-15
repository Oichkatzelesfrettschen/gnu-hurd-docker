# Control Plane (Canonical)

The “control plane” for this repo is intentionally simple:

- **Container lifecycle**: Compose (`docker compose` / `podman-compose`)
- **QEMU lifecycle**: `entrypoint.sh` builds and `exec`s a QEMU command
- **Observability**: container logs + QEMU telnet endpoints

## Primary control channels

- Container logs: `docker compose logs -f gnu-hurd-dev`
- Serial console: `telnet localhost 5555`
- QEMU monitor (HMP): `telnet localhost 9999`

## What is not implemented (yet)

- QMP socket exposure and structured automation APIs are not currently part of the default runtime.

## Legacy

An older, more ambitious “control plane” design (including QMP workflows) is preserved at `docs/02-ARCHITECTURE/archive/CONTROL-PLANE-LEGACY.md`.
