# Port Mapping (Canonical)

This repo uses a two-step forwarding chain:

1. **Host → container** via Compose `ports:`
2. **Container → guest** via QEMU user-mode networking (`hostfwd=...`)

## Defaults

| Purpose | Host | Container | Guest |
|--------|------|-----------|------|
| SSH | 2222 | 2222 | 22 |
| HTTP | 8080 | 8080 | 80 |
| Serial console (telnet) | 5555 | 5555 | N/A |
| QEMU monitor (telnet) | 9999 | 9999 | N/A |
| VNC (optional) | 5900 | 5900 | N/A |
| noVNC (optional) | 6080 | 8080 | N/A |

VNC/noVNC are enabled only when starting with the VNC overlay (`./scripts/docker-orchestration.sh up-vnc`).

## Changing host ports

Change the host-side port mapping via environment variables (or a `.env` file). For example:

```yaml
SSH_PORT: 2223
HTTP_PORT: 8081
SERIAL_PORT: 5556
MONITOR_PORT: 9998
```

The QEMU `hostfwd` values remain `tcp::2222-:22` inside the container, so only the host-side mapping changes.

## Legacy

An older, inconsistent port mapping document is preserved at `docs/03-CONFIGURATION/archive/PORT-MAPPING-LEGACY.md`.
