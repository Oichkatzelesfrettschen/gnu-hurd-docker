# Docker Compose Guide (Canonical)

This repo uses a small set of Compose files to keep “portable defaults” and “dev conveniences” separate.

## Files

- `docker-compose.yml`: baseline service definition (`gnu-hurd-dev`) using an engine-managed volume (`hurd-disk`)
- `docker-compose.override.yml`: local dev override (builds from local `Dockerfile`)
- `docker-compose.bind.yml`: dev override (bind-mount `./images` → `/opt/hurd-image`)
- `docker-compose.kvm.yml`: optional KVM device mount (`/dev/kvm`) for Linux x86_64 hosts
- `docker-compose.vnc.yml`: optional VNC + noVNC stack (pinned image digests)

## Recommended commands

```bash
# Dev default (bind mount)
docker compose -f docker-compose.yml -f docker-compose.bind.yml up -d

# Dev + KVM (Linux x86_64 only)
docker compose -f docker-compose.yml -f docker-compose.bind.yml -f docker-compose.kvm.yml up -d

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
