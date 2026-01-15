# CLI Orchestration

This repository supports Docker and Podman. The canonical wrapper is `scripts/docker-orchestration.sh`, which centralizes Compose file selection and naming.

If you need the previous, long-form orchestration guide (including legacy service names), see `docs/04-OPERATION/archive/CLI-ORCHESTRATION-LEGACY.md`.

## Common commands

Check runtime compatibility (Docker vs Podman, KVM availability):

```bash
./scripts/docker-orchestration.sh check
```

Start (dev bind mode, uses `docker-compose.bind.yml`):

```bash
./scripts/docker-orchestration.sh up
```

Start (dev bind + KVM, Linux x86_64 only):

```bash
./scripts/docker-orchestration.sh up-kvm
```

Start (portable volume mode, uses `docker-compose.yml` only):

```bash
AUTO_DOWNLOAD_IMAGE=1 ./scripts/docker-orchestration.sh up-volume
```

Stop:

```bash
./scripts/docker-orchestration.sh down
```

Logs:

```bash
./scripts/docker-orchestration.sh logs
```

Shell inside container:

```bash
./scripts/docker-orchestration.sh shell
```

