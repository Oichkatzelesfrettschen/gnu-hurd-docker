# Monitoring

This guide focuses on monitoring the container (`gnu-hurd-dev`) and the QEMU guest it runs.

If you need the previous, long-form monitoring guide (including legacy container names and historical tuning notes), see `docs/04-OPERATION/archive/MONITORING-LEGACY.md`.

## Container status and logs

```bash
make ps
make logs
```

Using Docker Compose directly:

```bash
docker compose ps
docker compose logs -f gnu-hurd-dev
```

## Resource usage

```bash
docker stats gnu-hurd-dev
docker inspect gnu-hurd-dev --format '{{json .HostConfig}}' | jq .
```

## Guest reachability (SSH)

```bash
nc -zv localhost 2222
ssh -p 2222 root@localhost true
```

If SSH is not available yet, use the serial console (`telnet localhost 5555`) to debug boot and network state.

## QEMU debug surfaces

- Monitor (telnet): `telnet localhost 9999`
- Serial (telnet): `telnet localhost 5555`

## Health check

The container health check runs `/opt/scripts/health-check.sh` (in-container). Inspect health:

```bash
docker inspect gnu-hurd-dev --format '{{json .State.Health}}' | jq .
```

