# Docker + QEMU CLI Cheatsheet

This document is a compact, current cheatsheet for interacting with the running container (`gnu-hurd-dev`) and its embedded QEMU guest.

If you need the previous, long-form document (including legacy service names), see `docs/04-OPERATION/archive/DOCKER-QEMU-CLI-LEGACY.md`.

## Container

```bash
docker compose ps
docker compose logs -f gnu-hurd-dev
docker exec -it gnu-hurd-dev bash
```

## Guest access

```bash
ssh -p 2222 root@localhost
telnet localhost 5555   # serial
telnet localhost 9999   # monitor
```

## Inspect QEMU

```bash
docker exec gnu-hurd-dev pgrep -a qemu-system-x86_64
docker exec gnu-hurd-dev ps aux | rg qemu-system-x86_64
```

