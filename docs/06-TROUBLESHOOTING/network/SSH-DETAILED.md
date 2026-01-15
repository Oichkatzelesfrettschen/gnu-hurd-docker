# SSH Troubleshooting (Detailed)

This document covers SSH troubleshooting for the current Debian GNU/Hurd **x86_64 guest** running inside the `gnu-hurd-dev` container.

The previous research-heavy document (including i386-era notes) is preserved at `docs/06-TROUBLESHOOTING/network/archive/SSH-DETAILED-LEGACY.md`.

## Quick checks

1. Confirm the container is up:

```bash
docker compose ps
```

2. Confirm the host port is reachable:

```bash
nc -zv localhost 2222
```

3. Try SSH with verbose output:

```bash
ssh -vvv -p 2222 root@localhost
```

## If SSH is not ready

- Use the serial console: `telnet localhost 5555`
- Verify the guest booted far enough to present a login prompt

## Credentials and expectations

Default development credentials (after provisioning) and security recommendations live in `docs/08-REFERENCE/CREDENTIALS.md`.

