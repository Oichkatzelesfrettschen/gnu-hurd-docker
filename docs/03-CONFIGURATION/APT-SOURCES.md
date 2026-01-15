# APT sources (Canonical)

This repo does not pin a global `apt` snapshot timestamp for the Debian GNU/Hurd guest. The upstream pre-installed image from cdimage comes with its own `sources.list` configuration.

## Recommended approach

- Start from the upstream image’s default APT sources.
- If you need reproducible builds inside the guest, use snapshot services intentionally and document the chosen timestamp in your own project or CI logs.

## Primary references

- Debian GNU/Hurd port info: https://www.debian.org/ports/hurd/
- Upstream image directory (ports/13.0 hurd-amd64): `https://cdimage.debian.org/cdimage/ports/13.0/hurd-amd64/`

## Legacy

An older, timestamp-pinned APT sources document is preserved at `docs/03-CONFIGURATION/archive/APT-SOURCES-LEGACY.md`.
