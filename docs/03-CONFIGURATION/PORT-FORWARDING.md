# Port Forwarding

This project uses QEMU user-mode networking (`-nic user,...`) inside the container to provide simple NAT and host port forwards.

If you need the previous, long-form document (including legacy service names and historical examples), see `docs/03-CONFIGURATION/archive/PORT-FORWARDING-LEGACY.md`.

## Defaults

By default, the guest exposes:

- SSH: host `localhost:2222` → container `:2222` → guest `:22`
- HTTP: host `localhost:8080` → container `:8080` → guest `:80`

These defaults are defined in:

- `compose.yaml` (host↔container port mappings)
- `entrypoint.sh` (QEMU `hostfwd=` rules inside `-nic user,...`)

## Change host ports (recommended)

To avoid conflicts on the host, change only the Compose mapping and keep QEMU listening on the same container ports.

Example (host `2223` to container `2222`):

```yaml
services:
  gnu-hurd-dev:
    ports:
      - "2223:2222"
```

## Add additional guest forwards (advanced)

Set `QEMU_HOSTFWDS` to a comma-separated list of QEMU `hostfwd` rules (without the `hostfwd=` prefix).

Example (add HTTPS 443):

```bash
QEMU_HOSTFWDS="tcp::2222-:22,tcp::8080-:80,tcp::8443-:443" \
  make up
```

Then map host port `8443` to container port `8443` in Compose as needed.

## Debugging

- Check the container is listening: `docker exec gnu-hurd-dev ss -tlnp`
- Check QEMU args: `docker exec gnu-hurd-dev ps aux | rg -- '-nic '`
- Use the monitor: `telnet localhost 9999`

