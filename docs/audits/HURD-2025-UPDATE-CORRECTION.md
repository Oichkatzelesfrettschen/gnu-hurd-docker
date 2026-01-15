# Debian GNU/Hurd ports/13.0 Reality Check (Correction)

This repo previously contained conflicting claims about the Debian GNU/Hurd ports/13.0 image “snapshot date” (e.g., `20251105`). Those claims were **not** supported by the upstream cdimage directory contents.

## What upstream actually shows

Upstream directory: `https://cdimage.debian.org/cdimage/ports/13.0/hurd-amd64/`

- The directory contains a dated build: `debian-hurd-amd64-20250807.*`
- The “generic” artifacts (e.g., `debian-hurd.img.tar.xz`) are present and correspond to the same build set.
- The upstream `README.txt` calls this “Debian GNU/Hurd 2025 "Trixie" - Unofficial hurd-amd64”.

## How to verify (primary source)

```bash
curl -fsSL https://cdimage.debian.org/cdimage/ports/13.0/hurd-amd64/ | grep -E 'debian-hurd-amd64-[0-9]{8}\\.img\\.tar\\.xz' | head
curl -fsSL https://cdimage.debian.org/cdimage/ports/13.0/hurd-amd64/README.txt | head
```

## Repository policy after this correction

- Do **not** hardcode an image “snapshot date” in docs or scripts unless it is backed by a primary upstream source.
- Prefer using `debian-hurd.img.tar.xz` + `SHA256SUMS` verification (as implemented by `scripts/download-image.sh`).
- When mentioning a dated build, phrase it as “currently `20250807` (check cdimage for updates)”.
