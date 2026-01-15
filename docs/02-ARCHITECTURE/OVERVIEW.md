# Architecture Overview (Canonical)

GNU/Hurd Docker runs a full Debian GNU/Hurd system as a **QEMU virtual machine**. The container (Docker/Podman) only hosts the QEMU process and related tooling.

## Upstream guest image

- Source: `https://cdimage.debian.org/cdimage/ports/13.0/hurd-amd64/`
- Preferred download artifact: `debian-hurd.img.tar.xz` (verify with `SHA256SUMS`)
- Current dated build on cdimage: `debian-hurd-amd64-20250807.*` (this changes; do not hardcode dates)

## Container/Compose model

- Service/container name: `gnu-hurd-dev`
- Baseline Compose (`docker-compose.yml`): uses an engine-managed volume (`hurd-disk`) mounted at `/opt/hurd-image`
- Dev default (`docker-compose.bind.yml`): bind-mounts `./images` to `/opt/hurd-image`
- Optional KVM (`docker-compose.kvm.yml`): mounts `/dev/kvm` (Linux x86_64 hosts only)

## Runtime invariants

- Guest: x86_64-only (`/usr/bin/qemu-system-x86_64` inside container)
- Container platform: `linux/amd64` and `linux/arm64`
- Acceleration:
  - Linux x86_64 + `/dev/kvm` → KVM
  - everything else → TCG (software emulation)

## Disk image layout

- Container path: `/opt/hurd-image/debian-hurd-amd64.qcow2`
- Host bind path (dev): `./images/debian-hurd-amd64.qcow2`
- Primary setup path: `./scripts/setup-hurd-amd64.sh` (downloads + converts + verifies)

## Networking and access

QEMU uses user-mode networking (NAT) with port forwards:

- SSH: `localhost:2222` → guest `:22`
- HTTP: `localhost:8080` → guest `:80`
- Serial console: `telnet localhost:5555`
- QEMU monitor: `telnet localhost:9999`
- Optional VNC/noVNC: start with `./scripts/docker-orchestration.sh up-vnc` then use `localhost:5900` or `http://localhost:6080/vnc.html`

## File sharing

- Host ↔ container: `./share` bind-mounted to `/share`
- Host ↔ guest:
  - Recommended: SSH/SCP once SSH is available
  - Experimental: QEMU 9p when `ENABLE_9P=1` (mount tag `hostshare`)

## Legacy material

The previous (inconsistent) architecture draft is preserved at `docs/02-ARCHITECTURE/archive/OVERVIEW-LEGACY.md`.
