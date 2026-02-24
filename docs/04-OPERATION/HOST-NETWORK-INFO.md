# Host network info (CachyOS)

This document describes how the repository is currently exposed on the host network, and what you need to change to connect from another machine.

## Current host IP

- LAN interface: `br0`
- Host LAN IP: `10.0.0.98`
- Default gateway: `10.0.0.1`

## Firewall status (UFW)

- `ufw` is enabled
- Default policy: `deny (incoming)`, `allow (outgoing)`

By default, this repo binds interactive services to `127.0.0.1` (localhost-only), so UFW rules do not matter unless you explicitly bind to the LAN IP / `0.0.0.0`.

## Ports used by this repo

When running with VNC/noVNC overlay:

- noVNC: `NOVNC_PORT` (default `6080`) via `docker-compose.vnc.yml`
- VNC: `VNC_PORT` (default `5900`) via `docker-compose.vnc.yml`
- QEMU monitor (telnet): `MONITOR_PORT` (default `9999`)
- QEMU serial (telnet): `SERIAL_PORT` (default `5555`)
- SSH forward to guest: `SSH_PORT` (default `2222`)
- HTTP forward to guest: `HTTP_PORT` (default `8080`)

## Allow LAN access (recommended: noVNC only)

Expose only noVNC, and keep raw VNC on localhost:

```bash
NOVNC_BIND=0.0.0.0 VNC_BIND=127.0.0.1 make up-vnc
```

Allow from the LAN subnet:

```bash
sudo ufw allow from 10.0.0.0/24 to any port 6080 proto tcp
```

Connect from another PC:

- `http://10.0.0.98:6080/vnc.html`

## Safer option: SSH tunnel

Keep binds on localhost (default) and tunnel from another PC:

```bash
ssh -L 6080:127.0.0.1:6080 <user>@10.0.0.98
```

Then open:

- `http://127.0.0.1:6080/vnc.html`

