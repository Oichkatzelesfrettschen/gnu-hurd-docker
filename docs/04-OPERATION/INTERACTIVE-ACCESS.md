# Interactive Access

This project exposes multiple “control surfaces” for a single Debian GNU/Hurd **x86_64 guest** running under QEMU inside the `gnu-hurd-dev` container.

If you need the previous, long-form guide (including historical examples), see `docs/04-OPERATION/archive/INTERACTIVE-ACCESS-LEGACY.md`.

## Prerequisites

- A disk image is present at host `./images/debian-hurd-amd64.qcow2` (bind mode), or you are using volume mode with auto-download enabled.
- The container is running (`gnu-hurd-dev`).

Start (dev bind mode):

```bash
./scripts/setup-hurd-amd64.sh
./scripts/docker-orchestration.sh up
```

Start (portable volume mode, auto-download on first run):

```bash
AUTO_DOWNLOAD_IMAGE=1 ./scripts/docker-orchestration.sh up-volume
```

## Access channels

### SSH (recommended)

- Host: `localhost:2222`
- Guest: `:22` (via QEMU user-mode networking)

```bash
ssh -p 2222 root@localhost
```

Default development credentials and hardening notes live in `docs/08-REFERENCE/CREDENTIALS.md`.

### Serial console (boot/debug)

- Host: `localhost:5555` (telnet)

```bash
telnet localhost 5555
```

### QEMU monitor (debug/control)

- Host: `localhost:9999` (telnet)

```bash
telnet localhost 9999
```

### VNC (optional)

- Host: `localhost:${VNC_PORT:-5900}`

Enable VNC:

```bash
./scripts/docker-orchestration.sh up-vnc
```

### noVNC (optional, browser)

- Host: `http://localhost:6080/vnc.html`

```bash
./scripts/docker-orchestration.sh up-vnc
```

## Container-level access (not the guest)

Open a shell inside the container:

```bash
./scripts/docker-orchestration.sh shell
```

Follow logs:

```bash
./scripts/docker-orchestration.sh logs
```
