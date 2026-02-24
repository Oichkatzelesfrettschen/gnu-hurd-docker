# Building guest images (Canonical)

This repo’s default workflow uses the upstream Debian GNU/Hurd pre-installed image from `https://cdimage.debian.org/cdimage/ports/13.0/hurd-amd64/`, converted to QCOW2 as `images/debian-hurd-amd64.qcow2`.

## Recommended approach

1. Create/update the disk image (with checksum verification):
   - `./scripts/setup-hurd-amd64.sh`
2. Run the VM (dev default):
   - `make up`
3. Customize inside the guest (SSH: `ssh -p 2222 root@localhost`)
4. Persist changes by shutting down cleanly (guest `shutdown -h now`), then snapshot on the host:
   - `./scripts/manage-snapshots.sh create <name>`

## If you need a distributable pre-provisioned image

- Treat it as a separate artifact (QCOW2) and publish it outside git (e.g., a release asset).
- Keep container images and guest disk images separate: the container image hosts QEMU; the QCOW2 is the guest OS state.

## Legacy

An older “riced image” build walkthrough is preserved at `docs/05-CI-CD/images/archive/BUILDING-LEGACY.md`.
