# Validation (Canonical)

This repo includes validation scripts to catch configuration regressions early.

## Host-side checks

- `./scripts/validate-config.sh` validates:
  - required files exist
  - shell scripts pass `shellcheck -S error`
  - Compose YAML parses
  - key invariants (service name, overlays, image path expectations)
- `./scripts/smoke-host.sh` runs lightweight sanity checks without starting the VM.

## Runtime checks

- Container logs: `./scripts/docker-orchestration.sh logs`
- Healthcheck: `/opt/scripts/health-check.sh` (runs inside the container)

## Legacy

An older host-specific validation report is preserved at `docs/06-TROUBLESHOOTING/archive/VALIDATION-LEGACY.md`.
