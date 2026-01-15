# gnu-hurd-docker — Project Reality Check (Gemini Notes)

## What this repository actually is

This repository runs **Debian GNU/Hurd (x86_64)** inside a **QEMU virtual machine**.
Docker/Podman host the QEMU process and expose ports/volumes. This is **not** “Hurd in a container”.

## Non-negotiable invariants

- **Guest OS**: Debian GNU/Hurd (**x86_64 only**).
- **Container architecture**: can be `linux/amd64` or `linux/arm64` (QEMU emulates x86_64 on non-x86 hosts).
- **Acceleration**:
  - **KVM works only on Linux x86_64 hosts** for an x86_64 guest.
  - On arm64 hosts, QEMU must use **TCG (software emulation)**.
- **Reliability note**: some Debian GNU/Hurd amd64 qcow2 images hit IDE DMA I/O errors under KVM; this repo defaults to TCG for IDE on `pc` unless `FORCE_KVM=1`.
- **Upstream image source**: `https://cdimage.debian.org/cdimage/ports/13.0/hurd-amd64/` (current dated build on cdimage is `20250807`; do not hardcode dates).
- **Disk image**: expected at `./images/debian-hurd-amd64.qcow2` on the host (dev bind mode), mounted to `/opt/hurd-image/debian-hurd-amd64.qcow2` in the container.

## Primary entrypoints

- Download + convert official image: `./scripts/setup-hurd-amd64.sh`
- Validate repo consistency: `./scripts/validate-config.sh`
- Host smoke check: `./scripts/smoke-host.sh`
- Orchestration (Docker or Podman): `./scripts/docker-orchestration.sh up` / `up-kvm`

## Key fixes applied (audit continuation)

- Removed a hard `x86_64` host requirement in `entrypoint.sh` and made KVM selection **host-arch-aware**.
- Fixed a config bug: `docker-compose.yml` now allows overriding `QEMU_RAM`, `QEMU_SMP`, and `ENABLE_VNC` via environment variables (previously hardcoded).
- Added reliability guardrails:
  - `AUTO_DISABLE_KVM_FOR_IDE=1` (default) avoids KVM+IDE DMA failures on affected images.
  - `FORCE_KVM=1` overrides the guardrail for experimentation.
- Standardized Compose strategy:
  - `docker-compose.yml` is the portable baseline (engine-managed `hurd-disk` volume).
  - `docker-compose.bind.yml` is the dev default (`./images` bind mount).
  - `docker-compose.kvm.yml` is the Linux x86_64 KVM overlay.
- Adjusted runtime privilege model:
  - `Dockerfile` runs as root; `entrypoint.sh` drops to `hurd` when mounts are writable (via `gosu`), otherwise runs QEMU as root (volume-friendly).
- Fixed image preparation flow:
  - `scripts/download-image.sh` verifies `SHA256SUMS` and no longer assumes a fixed extracted `.img` filename.
  - `scripts/setup-hurd-amd64.sh` wraps `download-image.sh` and points to the canonical run commands.
  - Optional in-container download supported with `AUTO_DOWNLOAD_IMAGE=1`.
- Fixed packaging bugs:
  - `PKGBUILD` is now `arch=('any')`.
  - Host QEMU moved from hard dependency to optional dependency.
  - Documentation path fixed (previously referenced a missing `requirements.md`).

## Known remaining risks (high-value)

- Some docs remain “report-like” and may still contain historical inaccuracies (especially under `docs/reports/` and `docs/07-RESEARCH-AND-LESSONS/`).
- Some research/audit documents still include legacy service names; canonical guides avoid this by archiving the long-form docs under `docs/**/archive/`.
- Guest SSH readiness is not provable headlessly on all images:
  - Serial is often blank (no login prompt); VNC/noVNC is the practical provisioning path.
  - On some images `sshd` can crash at boot; validate via SSH banner (`./scripts/check-ssh-banner.sh`), not just port-open checks.
- Full end-to-end runtime validation still requires actually booting the VM and verifying SSH + VNC/noVNC + monitor paths on at least one amd64 host and one arm64 host (TCG).
