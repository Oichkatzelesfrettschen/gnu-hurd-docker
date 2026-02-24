# CLI Orchestration

This repository supports Docker and Podman via a Compose-native control plane driven by `Makefile`.
The canonical entrypoint is `make` + Compose files (`compose.yaml`, `compose.*.yaml`) rather than a custom wrapper script.

If you need the previous, long-form orchestration guide (including legacy service names), see `docs/04-OPERATION/archive/CLI-ORCHESTRATION-LEGACY.md`.

## Common commands

Check runtime compatibility (Docker vs Podman, KVM availability):

```bash
CONTAINER_RUNTIME=docker make compose-config
```

Build with Bake (Docker Buildx):

```bash
make build
```

Start (dev bind mode, uses `compose.bind.yaml`):

```bash
make up
```

Start (dev bind + KVM, Linux x86_64 only):

```bash
make up-kvm
```

Start (portable volume mode, uses `compose.yaml` only):

```bash
AUTO_DOWNLOAD_IMAGE=1 make up-volume
```

Stop:

```bash
make down
```

Logs:

```bash
make logs
```

Shell inside container:

```bash
make shell
```

## Podman Provider Pinning

Use Podman with an explicit compose provider to avoid accidental delegation:

```bash
PODMAN_COMPOSE_PROVIDER=podman-compose CONTAINER_RUNTIME=podman make up-podman
```

Optional persistent config template:

```bash
mkdir -p ~/.config/containers
cp config/podman/containers.conf ~/.config/containers/containers.conf
```
