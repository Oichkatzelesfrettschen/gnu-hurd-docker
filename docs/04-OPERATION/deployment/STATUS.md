# Deployment Status (Canonical)

This repository runs Debian GNU/Hurd as a QEMU virtual machine hosted inside a container.

## Current state

- Canonical service/container: `gnu-hurd-dev`
- Container runs unprivileged by default (`privileged: false`)
- Optional KVM acceleration (Linux x86_64 hosts only) via `docker-compose.kvm.yml`
- Disk image is external (not stored in git): `./images/debian-hurd-amd64.qcow2` (bind mode) or `hurd-disk` volume (portable mode)

## Recommended deployment flow

1. Prepare the disk image: `./scripts/setup-hurd-amd64.sh`
2. Validate config: `./scripts/validate-config.sh`
3. Start (dev default): `./scripts/docker-orchestration.sh up`

## Legacy

The previous draft status document is preserved at `docs/04-OPERATION/deployment/archive/STATUS-LEGACY.md`.
