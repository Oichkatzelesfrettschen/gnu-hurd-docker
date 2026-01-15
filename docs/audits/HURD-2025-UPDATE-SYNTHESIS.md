# Debian GNU/Hurd ports/13.0 Upstream Alignment (Synthesis)

## Primary sources

- Upstream images + checksums: `https://cdimage.debian.org/cdimage/ports/13.0/hurd-amd64/`
- Upstream release notes for this directory: `README.txt` in that same directory.

## What this repository uses

- Download artifact: `debian-hurd.img.tar.xz`
- Integrity: `SHA256SUMS` verification (unless `SKIP_CHECKSUM=1`)
- Output disk: `images/debian-hurd-amd64.qcow2`

## Why this matters

This repo is a **QEMU-in-container** workflow:

- Container image provides QEMU + tooling (Ubuntu 24.04 base).
- Guest OS state lives in a QCOW2 disk image that is *not* stored in git.
- Most operational “truth” should be derived from:
  - upstream cdimage artifacts + checksums
  - this repo’s scripts and Compose files

## Known upstream build identifier

At the time of verification, the upstream directory contained a dated build `20250807` (for example `debian-hurd-amd64-20250807.img.tar.xz`). This can change over time; scripts should prefer the generic artifact names and checksum verification.

## Action items implemented in-repo

- Docs updated to stop hardcoding unsupported dates (e.g., `20251105`).
- Scripts updated to verify `SHA256SUMS` and to avoid assuming a fixed extracted `.img` filename.
