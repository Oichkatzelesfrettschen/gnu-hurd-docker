# GNU/Hurd Docker - Quick Reference (Canonical)

## Host-side setup

```bash
./scripts/setup-hurd-amd64.sh
./scripts/validate-config.sh
./scripts/validate-security-config.sh
./scripts/smoke-host.sh
```

## Start/stop (Docker or Podman)

```bash
# Start (dev default: bind-mount ./images)
./scripts/docker-orchestration.sh up

# Logs
./scripts/docker-orchestration.sh logs

# Stop
./scripts/docker-orchestration.sh down
```

## Access

```bash
ssh -p 2222 root@localhost
telnet localhost 5555   # serial
telnet localhost 9999   # QEMU monitor
```

## First-run self-heal (optional)

If you start in volume mode and the disk image is missing:

```bash
AUTO_DOWNLOAD_IMAGE=1 ./scripts/docker-orchestration.sh up-volume
```

## Legacy

An older quick reference with obsolete flags is preserved at `docs/08-REFERENCE/archive/QUICK-REFERENCE-LEGACY.md`.
