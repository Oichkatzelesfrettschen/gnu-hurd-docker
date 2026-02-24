# Latest Debian GNU/Hurd amd64 Workflow

This guide defines two supported image tracks:

1. `release` track (reproducible baseline): Debian ports `13.0`
2. `latest` track (fresh upstream): Debian ports `latest`
3. `daily-installer` track (freshest): Debian installer daily for `hurd-amd64`

The goal is to keep a stable baseline image while also allowing rapid validation against the newest upstream `hurd-amd64` image.

## Quick Commands

Baseline reproducible image:

```bash
make setup
make up
```

Fresh upstream latest image (keeps baseline image intact):

```bash
make setup-latest
make up-latest
```

Podman latest image path:

```bash
PODMAN_COMPOSE_PROVIDER=podman-compose CONTAINER_RUNTIME=podman make setup-latest
PODMAN_COMPOSE_PROVIDER=podman-compose CONTAINER_RUNTIME=podman make up-podman-latest
```

Fresh daily-installer path:

```bash
make setup-daily-installer
make up-installer
```

Podman daily-installer path:

```bash
PODMAN_COMPOSE_PROVIDER=podman-compose CONTAINER_RUNTIME=podman make setup-daily-installer
PODMAN_COMPOSE_PROVIDER=podman-compose CONTAINER_RUNTIME=podman make up-podman-installer
```

## How Latest Resolution Works

Use:

```bash
make resolve-latest-image
```

This calls `scripts/resolve-latest-hurd-amd64.sh`, which reads the `ports/latest/hurd-amd64` index and returns the newest dated artifact (`debian-hurd-amd64-YYYYMMDD.img.tar.xz`), plus checksum when available.

Checksum policy in `scripts/download-image.sh`:

1. Prefer `SHA256SUMS`
2. Fallback to `MD5SUMS` only when SHA256 is not published by upstream on that track

If no checksum entry is published for the resolved latest artifact, `make setup-latest` currently proceeds with `SKIP_CHECKSUM=1` and emits a warning.

## Image Naming and Selection

`make setup-latest` produces:

- `images/debian-hurd-amd64-<YYYYMMDD>.qcow2` (date-stamped immutable image)
- `images/debian-hurd-amd64.latest.qcow2` (moving alias symlink)

Runtime image selection uses:

- `HURD_IMAGE_BASENAME` (default: `debian-hurd-amd64.qcow2`)

Examples:

```bash
HURD_IMAGE_BASENAME=debian-hurd-amd64.latest.qcow2 make up
HURD_IMAGE_BASENAME=debian-hurd-amd64-20251105.qcow2 make up
```

## Manual Full Configuration (Latest Image)

After `make up-latest`:

1. Enable SSH from serial console automation:

```bash
NONINTERACTIVE=1 SERIAL_PORT=5555 ./scripts/install-ssh-hurd.sh
```

2. Normalize apt sources for Debian ports:

```bash
ROOT_PASS=root ./scripts/fix-sources-hurd.sh -h localhost -p 2222
```

3. Connect and run environment setup in guest:

```bash
ssh -p 2222 root@localhost
# inside guest:
/opt/scripts/install-hurd-environment.sh --dev
```

4. Optional workstation setup:

```bash
# inside guest:
/opt/scripts/install-hurd-environment.sh --gui
```

## Automated Reproducibility Attempt

Best-effort one-command flow:

```bash
./scripts/bootstrap-latest-hurd.sh
```

Podman variant:

```bash
PODMAN_COMPOSE_PROVIDER=podman-compose CONTAINER_RUNTIME=podman ./scripts/bootstrap-latest-hurd.sh
```

What it does:

1. Resolves/downloads latest upstream image
2. Boots container with latest alias
3. Runs provisioning flow (`bringup-and-provision.sh`) in noninteractive mode

## Daily Installer Track (When You Need Newer Than ports/latest)

As of `2026-02-24`, `ports/latest/hurd-amd64` resolves to `debian-hurd-amd64-20251105.img.tar.xz`, while installer dailies on `d-i.debian.org` continue into February 2026.

Use:

```bash
make resolve-latest-daily-installer
make setup-daily-installer
```

`setup-daily-installer` does three things:

1. Resolves latest dated installer build (`YYYYMMDD-HH:MM`)
2. Downloads `netboot/mini.iso` into `infrastructure/cache/images/installers/` and verifies SHA256 when published
3. Creates a fresh target QCOW2 disk in `images/` and a stable alias: `debian-hurd-amd64.fresh.qcow2`

Installer boot defaults:

- `QEMU_CDROM=/opt/hurd-installer/debian-hurd-amd64-installer.latest-mini.iso`
- `QEMU_BOOT_ORDER=d`
- `HURD_IMAGE_BASENAME=debian-hurd-amd64.fresh.qcow2`

After OS install completes, boot the fresh disk without installer media:

```bash
QEMU_CDROM= QEMU_BOOT_ORDER=c HURD_IMAGE_BASENAME=debian-hurd-amd64.fresh.qcow2 make up
```

## Notes

- Latest-track reproducibility is "date-pinned after resolution". Keep the date-stamped QCOW2 for exact replay.
- Release-track reproducibility remains the default through `make setup` and `make up`.
