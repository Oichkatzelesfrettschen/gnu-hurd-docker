# Workflows (CI/CD)

This repository’s CI/CD is intentionally minimal: validate configuration, build/publish the container image, and (optionally) run host-side sanity checks.

If you need the previous, long-form CI document (including legacy service names and historical workflow drafts), see `docs/05-CI-CD/archive/WORKFLOWS-LEGACY.md`.

## Core goals

- Keep the container image multi-arch (`linux/amd64`, `linux/arm64`) while running an **x86_64 guest** under QEMU.
- Treat static analysis warnings as errors where possible (ShellCheck, link checks, YAML validation).
- Avoid “host dependency leakage” (the image should contain QEMU and its runtime deps).

## What should always pass locally

```bash
./scripts/validate-config.sh
./scripts/smoke-host.sh
python3 scripts/utils/link-scanner.py --docs-root docs
shellcheck -S warning entrypoint.sh scripts/*.sh scripts/lib/*.sh scripts/test-phases/*.sh
```

## Image build strategy

- Production pulls: `ghcr.io/oichkatzelesfrettschen/gnu-hurd-docker:latest`
- Local dev builds: `docker-compose.override.yml` switches the service to `build: .`

## Compose sanity checks

```bash
docker compose -f docker-compose.yml config >/dev/null
docker compose -f docker-compose.yml -f docker-compose.bind.yml config >/dev/null
docker compose -f docker-compose.yml -f docker-compose.kvm.yml config >/dev/null
```

