# Scripts Inventory and Consolidation Report

- generated_utc: 2026-02-25T08:07:57Z
- total_scripts: 109
- inventory_tsv: `scripts/inventory.tsv`

## Counts by Status

- active-core: 11
- active-support: 66
- conceptual-stub: 2
- legacy-archive: 4
- modular-canonical: 6
- shared-library: 9
- test-support: 11

## Active Core

- `scripts/build-hurd-unattended-iso.sh`
- `scripts/install-hurd-unattended.sh`
- `scripts/qemu-auto-verify.sh`
- `scripts/qemu-install-fsm.expect`
- `scripts/qemu-install-serial-fsm.sh`
- `scripts/qemu-matrix-runner.sh`
- `scripts/qemu-stall-probe.sh`
- `scripts/rebuild-hurd-unattended-iso.sh`
- `scripts/resolve-latest-hurd-amd64-daily-installer.sh`
- `scripts/setup-hurd-amd64-daily-installer.sh`
- `scripts/validate-config.sh`

## Modular Canonical

- `scripts/automation/audit/audit-scripts-inventory.sh`
- `scripts/automation/qemu/qemu-auto-verify.sh`
- `scripts/automation/qemu/qemu-install-serial-fsm.sh`
- `scripts/automation/qemu/qemu-matrix-runner.sh`
- `scripts/automation/qemu/qemu-stall-probe.sh`
- `scripts/automation/qemu/rebuild-hurd-unattended-iso.sh`

## Conceptual Stub

- `scripts/automation/stubs/vbox-conceptual-stub.sh`
- `scripts/vboxmanage-hurd.sh`

## Legacy Archive

- `scripts/archive/README.md`
- `scripts/archive/boot_hurd.sh`
- `scripts/archive/migrate-docs-2025-11.sh`
- `scripts/archive/test-docker-provision.sh`

## Synthesis Recommendations

- Keep wrappers at `scripts/*.sh` for compatibility, route implementation to `scripts/automation/*`.
- Centralize serial parsing/evidence helpers under `scripts/lib/installer/`.
- Treat VirtualBox flows as conceptual-only until QEMU matrix reaches stable pass criteria.
- Use `scripts/automation/qemu/` as canonical path for unattended, stall probe, verify, and matrix orchestration.
