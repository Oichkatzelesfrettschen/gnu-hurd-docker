# Pre-Provisioned Guest Disk Images (Canonical)

This repo’s CI/CD story splits into two independent artifacts:

1. **Container image**: provides QEMU + tooling (built from `Dockerfile`)
2. **Guest disk image (QCOW2)**: contains the Debian GNU/Hurd OS state

## Baseline guest disk

- Built locally with: `./scripts/setup-hurd-amd64.sh`
- Source: `https://cdimage.debian.org/cdimage/ports/13.0/hurd-amd64/`
- Integrity: `SHA256SUMS` verification (unless `SKIP_CHECKSUM=1`)

## Pre-provisioned guest disk (optional)

If you want faster CI or a ready-to-use dev environment, publish a prepared QCOW2 as a separate release asset:

- Create a snapshot inside the QCOW2 once the guest is configured (host-side):
  - `./scripts/manage-snapshots.sh create <tag>`
- Publish the resulting QCOW2 outside git (e.g., GitHub Release assets).

## Legacy

An older, partially host-specific pre-provisioning walkthrough is preserved at `docs/05-CI-CD/archive/PROVISIONED-IMAGE-LEGACY.md`.
