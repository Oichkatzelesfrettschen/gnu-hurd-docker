# Debian GNU/Hurd amd64 Latest Audit (as of 2026-02-24)

## Scope

Verify the newest upstream Debian GNU/Hurd `hurd-amd64` image and reconcile repo workflows so users can choose:

1. baseline reproducible image path
2. fresh upstream latest image path

## Upstream Evidence Snapshot

Checked URL:

- `https://cdimage.debian.org/cdimage/ports/latest/hurd-amd64/`
- `https://d-i.debian.org/daily-images/hurd-amd64/`

Observed in index:

- dated image artifacts include:
  - `debian-hurd-amd64-20250807.img.tar.xz`
  - `debian-hurd-amd64-20251105.img.tar.xz`
- newest dated artifact present: `debian-hurd-amd64-20251105.img.tar.xz`
- `README` / `README.txt` modified date shown: `2026-02-19`

Repro command:

```bash
./scripts/resolve-latest-hurd-amd64.sh report
```

Expected output shape:

```text
BASE_URL=...
ARTIFACT=debian-hurd-amd64-YYYYMMDD.img.tar.xz
BUILD_DATE=YYYYMMDD
CHECKSUM_TYPE=sha256|md5
CHECKSUM=...
```

## Result

As of audit date `2026-02-24`, the latest dated `hurd-amd64` image artifact resolved by tooling is:

- `debian-hurd-amd64-20251105.img.tar.xz`

Checksum caveat:

- `ports/latest/hurd-amd64` may not publish SHA256 entries for every dated top-level `.img.tar.xz` artifact.
- latest-track setup therefore falls back to available checksum files and may require (or auto-apply) `SKIP_CHECKSUM=1` when upstream lacks matching checksum entries.

Daily installer evidence:

- `https://d-i.debian.org/daily-images/hurd-amd64/` lists dated builds through `20260223-10:12`.
- `daily/` path provides `SHA256SUMS` and `netboot/mini.iso`.
- This can be newer than `ports/latest` prebuilt images and is now supported as a fresh-install path.

## Control-Plane Changes Applied

1. Added explicit latest resolver script:
   - `scripts/resolve-latest-hurd-amd64.sh`
2. Added latest setup wrapper with date-stamped QCOW2 + latest symlink:
   - `scripts/setup-hurd-amd64-latest.sh`
3. Added end-to-end bootstrap attempt:
   - `scripts/bootstrap-latest-hurd.sh`
4. Added daily-installer resolver/setup:
   - `scripts/resolve-latest-hurd-amd64-daily-installer.sh`
   - `scripts/setup-hurd-amd64-daily-installer.sh`
5. Added `make` targets:
   - `resolve-latest-image`, `setup-latest`, `up-latest`, `up-podman-latest`
   - `resolve-latest-daily-installer`, `setup-daily-installer`, `up-installer`, `up-podman-installer`
6. Added image selection variable in compose:
   - `HURD_IMAGE_BASENAME` via `QEMU_DRIVE=/opt/hurd-image/${HURD_IMAGE_BASENAME:-debian-hurd-amd64.qcow2}`
7. Added optional installer media runtime variables:
   - `QEMU_CDROM`, `QEMU_BOOT_ORDER`
8. Updated download checksum logic:
   - prefer SHA256, fallback to MD5 when upstream latest track does not publish SHA256

## Operational Paths

Baseline reproducible path:

```bash
make setup
make up
```

Fresh latest path:

```bash
make setup-latest
make up-latest
```

Podman latest path:

```bash
PODMAN_COMPOSE_PROVIDER=podman-compose CONTAINER_RUNTIME=podman make setup-latest
PODMAN_COMPOSE_PROVIDER=podman-compose CONTAINER_RUNTIME=podman make up-podman-latest
```

Daily installer (freshest) path:

```bash
make setup-daily-installer
make up-installer
```

Podman daily-installer path:

```bash
PODMAN_COMPOSE_PROVIDER=podman-compose CONTAINER_RUNTIME=podman make setup-daily-installer
PODMAN_COMPOSE_PROVIDER=podman-compose CONTAINER_RUNTIME=podman make up-podman-installer
```

## Compose/Podman Best-Practice Synthesis Applied

1. Use runtime-specific compose defaults instead of cross-runtime merge sets.
2. Prefer auto-assigned bridge subnets for Podman (avoid hardcoded CIDR collisions on host LAN/VPN ranges).
3. Use provider-direct execution (`podman-compose`) for deterministic Podman behavior when wrapper mode is unstable.
4. Keep image/media selection declarative via env vars (`HURD_IMAGE_BASENAME`, `QEMU_CDROM`, `QEMU_BOOT_ORDER`) rather than ad-hoc scripts.
