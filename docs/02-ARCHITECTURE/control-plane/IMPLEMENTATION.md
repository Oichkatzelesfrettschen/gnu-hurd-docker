# Control Plane Implementation (Current)

This document describes the **current** control surfaces exposed by the containerized QEMU guest. The older i386-focused brainstorm is preserved at `docs/02-ARCHITECTURE/control-plane/archive/IMPLEMENTATION-LEGACY.md`.

## What exists today

- **Container name/service**: `gnu-hurd-dev`
- **Guest OS**: Debian GNU/Hurd x86_64 (QEMU full-system VM)
- **Access channels**:
  - SSH: host `:2222` → guest `:22`
  - Serial console: host `:5555` (telnet)
  - QEMU monitor: host `:9999` (telnet)
  - Optional VNC/noVNC via `compose.vnc.yaml`
  - Optional 9p share: set `ENABLE_9P=1` (mount tag `hostshare`)

## What does not exist yet (explicit gaps)

- QMP socket exposure and automation (there is a `scripts/qmp-helper.py`, but Compose/entrypoint do not expose QMP by default)
- Automated in-guest provisioning as a first-class workflow (scripts exist, but are not run automatically)

## Primary entrypoints

- Compose control plane: `Makefile` + `compose.yaml` overlays
- Runtime launcher: `entrypoint.sh`
- Standalone launcher: `scripts/run-hurd-qemu.sh`
