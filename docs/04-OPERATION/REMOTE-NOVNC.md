# Remote noVNC (LAN access)

By default, `docker-compose.vnc.yml` binds both VNC and noVNC to `127.0.0.1` for safety.
If you need to connect from another computer on your LAN, you have two options:

## Option A (recommended): SSH tunnel (safe)

1. Keep defaults (localhost-only):
   - `NOVNC_BIND=127.0.0.1`
   - `VNC_BIND=127.0.0.1`

2. From another PC, create an SSH tunnel to the host:

```bash
ssh -L 6080:127.0.0.1:6080 <user>@<host-ip>
```

3. On the other PC, open:
   - `http://127.0.0.1:6080/vnc.html`

This avoids exposing an unauthenticated remote desktop service on your LAN.

## Option B: Bind to LAN IP (insecure unless firewalled)

1. Start with binds on all interfaces:

```bash
# Use 0.0.0.0 to listen on the LAN interface (insecure unless firewalled)
NOVNC_BIND=0.0.0.0 VNC_BIND=0.0.0.0 ./scripts/docker-orchestration.sh up-vnc
```

2. Ensure your firewall allows LAN access to the chosen ports (example for ufw):

```bash
# Example: allow only your LAN subnet (adjust subnet + ports as needed)
sudo ufw allow from 10.0.0.0/24 to any port 6080 proto tcp
sudo ufw allow from 10.0.0.0/24 to any port 5900 proto tcp
```

3. From another PC on your LAN, open:
   - `http://<host-ip>:6080/vnc.html`

### Notes for this host

- Host LAN IP: `10.0.0.98` (interface `br0`)
- UFW is enabled with default `deny (incoming)`.
- Your current Compose defaults bind to `127.0.0.1`, so LAN access requires `NOVNC_BIND=0.0.0.0`.
- If you use non-default ports (e.g. `NOVNC_PORT=6081`), you must update firewall rules accordingly.

## Quick recipe (this repo on this host)

1. Start VNC/noVNC and bind noVNC to LAN:

```bash
NOVNC_BIND=0.0.0.0 NOVNC_PORT=6081 VNC_PORT=5901 ./scripts/docker-orchestration.sh up-vnc
```

2. Allow from LAN subnet (this host uses `10.0.0.0/24`):

```bash
sudo ufw allow from 10.0.0.0/24 to any port 6081 proto tcp
```

3. Connect from another PC:

- `http://10.0.0.98:6081/vnc.html`

### Security notes

- The upstream `theasp/novnc` container provides no authentication by default.
- If you must expose it, restrict by source IP (LAN subnet only) and consider SSH tunneling anyway.
- Prefer exposing only `NOVNC_BIND` (6080) and keep `VNC_BIND` on `127.0.0.1` unless you specifically need raw VNC.
