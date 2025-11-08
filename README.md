# Debian GNU/Hurd x86_64 Docker Environment

Modern Docker-based development environment for **Debian GNU/Hurd x86_64** with native CPU passthrough and KVM acceleration.

## Quick Start

```bash
# Download and convert official x86_64 image
./scripts/setup-hurd-amd64.sh

# Start the VM
docker-compose up -d

# SSH access (wait 2-3 minutes for boot)
ssh -p 2223 root@localhost
```

**Default Credentials**:
- Username: `root`
- Password: (press Enter) or `root`

## Architecture

- **CPU**: Native x86_64 with host passthrough (KVM)
- **Cores**: 4
- **RAM**: 8 GB
- **Storage**: IDE (80 GB dynamic qcow2)
- **Network**: E1000 (proven stable with Hurd)

## Ports

| Service | Port | Access |
|---------|------|--------|
| SSH | 2223 | `ssh -p 2223 root@localhost` |
| HTTP | 8081 | `curl http://localhost:8081` |
| VNC | 5902 | `vncviewer localhost:5902` |
| Serial | 5556 | `telnet localhost 5556` |

## Features

- ✅ Native x86_64 CPU passthrough (full instruction set)
- ✅ KVM acceleration (60-90s boot time)
- ✅ Official Debian GNU/Hurd amd64 image (August 2025)
- ✅ IDE storage (guaranteed Hurd compatibility)
- ✅ Docker-based (reproducible, portable)
- ✅ VNC console access

## Requirements

- Docker + Docker Compose
- KVM support (`/dev/kvm`)
- Linux host (for KVM)

## Files

- `docker-compose.yml` - x86_64 VM configuration
- `Dockerfile` - Container image
- `entrypoint.sh` - QEMU launcher
- `scripts/setup-hurd-amd64.sh` - Image download/convert
- `PORT-MAPPING-GUIDE.md` - Port forwarding reference

## License

MIT
