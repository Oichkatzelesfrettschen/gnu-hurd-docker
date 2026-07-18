# Implementation Summary (Current)

This document replaces an older “completion report” that described an i386-focused, privileged-container design. That report is preserved for historical context at `docs/07-RESEARCH-AND-LESSONS/archive/IMPLEMENTATION-COMPLETE-LEGACY.md`.

## What is implemented today

- **Guest OS**: Debian GNU/Hurd **x86_64** running under QEMU
- **Container**: `gnu-hurd-dev` (multi-arch container; guest remains x86_64)
- **Orchestration**: `compose.yaml` baseline + overlays (`compose.bind.yaml`, `compose.kvm.yaml`, `compose.vnc.yaml`)
- **Acceleration**:
  - KVM only on Linux `x86_64` hosts with `/dev/kvm`
  - TCG fallback everywhere else (including `arm64` hosts)
- **Privilege model**:
  - `privileged: false` (device mapping is used for KVM when enabled)
  - Entry point may start as root to handle volume hygiene, then drops to user `hurd` when possible

## Canonical references

- Reality check: `gemini.md`
- System design: `docs/02-ARCHITECTURE/SYSTEM-DESIGN.md`
- QEMU config: `docs/02-ARCHITECTURE/QEMU-CONFIGURATION.md`
- Getting started: `docs/01-GETTING-STARTED/QUICKSTART.md`

