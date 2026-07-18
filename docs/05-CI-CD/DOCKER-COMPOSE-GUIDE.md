# Docker Compose Guide (Canonical)

This repo uses a small set of Compose files to keep “portable defaults” and “dev conveniences” separate.

## Files

- `compose.yaml`: baseline service definition (`gnu-hurd-dev`) using an engine-managed volume (`hurd-disk`)
- `compose.override.yaml`: local dev override (builds from local `Dockerfile`)
- `compose.bind.yaml`: dev override (bind-mount `./images` → `/opt/hurd-image`)
- `compose.kvm.yaml`: optional KVM device mount (`/dev/kvm`) for Linux x86_64 hosts
- `compose.vnc.yaml`: optional VNC + noVNC stack (pinned image digests)

## Recommended commands

```bash
# Dev default (bind mount)
docker compose -f compose.yaml -f compose.bind.yaml up -d

# Dev + KVM (Linux x86_64 only)
docker compose -f compose.yaml -f compose.bind.yaml -f compose.kvm.yaml up -d

# Portable volume mode
docker compose up -d
```

## Podman

Podman is supported via `podman-compose` (see `scripts/lib/container-runtime.sh`). Prefer using:

```bash
make up
```

## Legacy

The previous, more speculative compose guide is preserved at `docs/05-CI-CD/archive/DOCKER-COMPOSE-GUIDE-LEGACY.md`.
