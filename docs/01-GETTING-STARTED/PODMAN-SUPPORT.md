# Podman Support Guide

## Overview

This project supports both **Docker** and **Podman** as container runtimes. Podman support is best on Linux; on macOS/Windows it runs via a VM (Podman Machine) and performance/feature parity depends on that layer.

## What is Podman?

Podman (Pod Manager) is a daemonless container engine for developing, managing, and running OCI Containers. Key advantages:

- **Daemonless**: No background daemon required (unlike Docker)
- **Rootless**: Can run containers without root privileges
- **Docker-compatible**: Drop-in replacement for Docker CLI
- **Pod support**: Native Kubernetes pod support
- **Secure**: No single point of failure, better security model

## Installation

### Linux

#### Debian/Ubuntu
```bash
sudo apt-get update
sudo apt-get install -y podman podman-compose
```

#### Fedora/RHEL/CentOS
```bash
sudo dnf install -y podman podman-compose
```

#### Arch Linux
```bash
sudo pacman -S podman podman-compose
```

### macOS

```bash
# Install Podman
brew install podman

# Initialize Podman machine (required on macOS)
podman machine init
podman machine start

# Install podman-compose
pip3 install podman-compose
```

### Windows

```bash
# Using Windows Subsystem for Linux (WSL2)
# Install WSL2 first, then follow Linux instructions

# Or use Podman Desktop
# Download from: https://podman-desktop.io/
```

### BSD (Not Officially Supported)

This project does not currently validate Podman/Docker operation on BSD hosts. If you run an OCI runtime layer on BSD, expect to debug host-specific issues and run the Hurd guest in TCG mode.

## Quick Start with Podman

### Using Compose-Native Make Targets (Recommended)

The control plane is `make` + Compose files. For Podman, pin the compose provider:

```bash
PODMAN_COMPOSE_PROVIDER=podman-compose CONTAINER_RUNTIME=podman make up-podman
PODMAN_COMPOSE_PROVIDER=podman-compose CONTAINER_RUNTIME=podman make logs
PODMAN_COMPOSE_PROVIDER=podman-compose CONTAINER_RUNTIME=podman make down
```

### Using Podman Compose Directly

```bash
# Start services
podman-compose -f compose.yaml -f compose.bind.yaml up -d

# View logs
podman-compose logs -f

# Stop services
podman-compose -f compose.yaml -f compose.bind.yaml down
```

### Using Podman CLI Directly

```bash
# Build image
podman build -t gnu-hurd-docker .

# Run container (TCG, works on non-x86_64 hosts too)
podman run -d \
  --name gnu-hurd-dev \
  -p 127.0.0.1:2222:2222 \
  -p 127.0.0.1:5555:5555 \
  -v hurd-disk:/opt/hurd-image:rw \
  -v ./share:/share:rw \
  gnu-hurd-docker

# Bind-mount QCOW2 from repo instead of a volume:
#   -v ./images:/opt/hurd-image:rw

# Optional: add KVM on Linux x86_64 hosts
#   --device /dev/kvm
```

## Rootless Podman notes (important)

- Rootless Podman is a good default for **TCG mode** (no `/dev/kvm`).
- KVM acceleration requires `/dev/kvm` device access; rootless setups may need host-specific configuration (group membership, user namespace handling, SELinux labels) or a rootful Podman run.
- By default, this repo’s Compose files bind ports to `127.0.0.1` to avoid exposing SSH/serial/monitor on the LAN. If you need remote access, explicitly change the port bindings.

## Podman vs Docker: Key Differences

### Architecture

| Aspect | Docker | Podman |
|--------|--------|--------|
| Daemon | Requires dockerd | Daemonless |
| Root | Usually requires root | Rootless support |
| Socket | Docker socket (security risk) | No central socket |
| Process model | Client-server | Direct fork/exec |
| Pods | Not native | Native Kubernetes pods |

### Command Compatibility

Podman aims for Docker CLI compatibility:

```bash
# These are equivalent:
docker run ...     # Docker
podman run ...     # Podman

docker ps          # Docker  
podman ps          # Podman

docker build ...   # Docker
podman build ...   # Podman
```

For true drop-in replacement:
```bash
alias docker=podman
```

## Configuration for Podman

### KVM Access

Podman needs proper device access for KVM acceleration:

```bash
# Check KVM availability
ls -l /dev/kvm

# Add user to kvm group (Linux)
sudo usermod -a -G kvm $USER

# Logout and login for group changes to take effect
```

### User Namespace Configuration

For rootless Podman with KVM:

```bash
# Check current subuid/subgid
cat /etc/subuid
cat /etc/subgid

# If not present, add:
echo "$USER:100000:65536" | sudo tee -a /etc/subuid
echo "$USER:100000:65536" | sudo tee -a /etc/subgid
```

### Storage Driver

Configure storage driver in `/etc/containers/storage.conf`:

```toml
[storage]
driver = "overlay"

[storage.options.overlay]
mount_program = "/usr/bin/fuse-overlayfs"
```

## Platform-Specific Notes

### Linux

- **Best support**: Podman is native to Linux
- **KVM acceleration**: Full support with proper permissions
- **Rootless mode**: Fully functional
- **Performance**: Equivalent to Docker

Setup checklist:
- ✅ Install podman and podman-compose
- ✅ Add user to kvm group
- ✅ Configure user namespaces

### macOS

- **Podman Machine**: Requires VM (similar to Docker Desktop)
- **KVM acceleration**: Not available (uses QEMU TCG)
- **Apple Silicon**: Supported via multi-arch containers
- **Performance**: Slower than Linux (virtualization overhead)

Setup checklist:
- ✅ Install Podman via Homebrew
- ✅ Initialize Podman machine: `podman machine init`
- ✅ Start Podman machine: `podman machine start`
- ✅ Install podman-compose

### Windows (WSL2)

- **WSL2 Required**: Podman runs inside WSL2
- **Integration**: Works with Windows Podman Desktop
- **Performance**: Better than Docker Desktop for some workloads

Setup checklist:
- ✅ Install WSL2
- ✅ Install Ubuntu or similar in WSL2
- ✅ Follow Linux installation steps inside WSL2
- ✅ Optional: Install Podman Desktop for GUI

### BSD

- **FreeBSD**: Best BSD support
- **OpenBSD/NetBSD**: Limited support
- **Performance**: Native bhyve preferred for VMs

Setup checklist:
- ✅ Install podman package
- ✅ Install podman-compose via pip

## Troubleshooting

### Issue: "command not found: podman-compose"

**Solution**: Install podman-compose
```bash
pip3 install --user podman-compose
# Add to PATH if needed
export PATH=$PATH:~/.local/bin
```

### Issue: "permission denied: /dev/kvm"

**Solution**: Add user to kvm group
```bash
sudo usermod -a -G kvm $USER
# Logout and login
newgrp kvm  # Or logout/login
```

### Issue: "failed to create user namespace"

**Solution**: Configure subuid/subgid
```bash
echo "$USER:100000:65536" | sudo tee -a /etc/subuid
echo "$USER:100000:65536" | sudo tee -a /etc/subgid
podman system migrate
```

### Issue: "cannot connect to Podman socket"

**Solution**: Start Podman service (if using socket mode)
```bash
systemctl --user start podman.socket
export DOCKER_HOST=unix:///run/user/$UID/podman/podman.sock
```

### Issue: "macOS - podman machine not initialized"

**Solution**: Initialize and start machine
```bash
podman machine init --cpus 4 --memory 8192 --disk-size 50
podman machine start
```

## Performance Comparison

### Boot Time Comparison (GNU/Hurd x86_64)

| Platform | Runtime | Acceleration | Boot Time |
|----------|---------|--------------|-----------|
| Linux (Intel/AMD) | Docker | KVM | 30-60s |
| Linux (Intel/AMD) | Podman | KVM | 30-60s |
| Linux (ARM64) | Docker | TCG | 3-5min |
| Linux (ARM64) | Podman | TCG | 3-5min |
| macOS (Intel) | Docker | HVF | 1-2min |
| macOS (Intel) | Podman | HVF | 1-2min |
| macOS (Apple Silicon) | Docker | TCG | 3-5min |
| macOS (Apple Silicon) | Podman | TCG | 3-5min |
| Windows (WSL2) | Docker | KVM | 30-60s |
| Windows (WSL2) | Podman | KVM | 30-60s |

### Resource Usage

Podman generally uses:
- **Lower memory overhead** (no daemon)
- **Faster startup** (no daemon initialization)
- **Lower attack surface** (no privileged daemon)

## Advanced Features

### Rootless Containers

Run containers without root:

```bash
# Check if rootless is supported
podman info | grep rootless

# Run as non-root user
podman run --rm -it gnu-hurd-docker /bin/bash
```

### Pod Support

Podman supports Kubernetes-style pods:

```bash
# Create a pod
podman pod create --name hurd-pod -p 2222:2222

# Run container in pod
podman run -d --pod hurd-pod gnu-hurd-docker
```

### Systemd Integration

Generate systemd units for automatic startup:

```bash
# Generate systemd unit
podman generate systemd --name gnu-hurd-dev > ~/.config/systemd/user/gnu-hurd-dev.service

# Enable and start
systemctl --user enable hurd.service
systemctl --user start hurd.service
```

## Migration from Docker

### Quick Migration

1. Install Podman:
   ```bash
   # Linux
   sudo apt-get install podman podman-compose
   ```

2. Set alias:
   ```bash
   alias docker=podman
   echo "alias docker=podman" >> ~/.bashrc
   ```

3. Use existing compose.yaml:
   ```bash
   podman-compose -f compose.yaml -f compose.bind.yaml up -d
   ```

### Full Migration

1. **Stop Docker services**:
   ```bash
   podman-compose -f compose.yaml -f compose.bind.yaml down
   ```

2. **Export images** (optional):
   ```bash
   docker save gnu-hurd-docker > gnu-hurd-docker.tar
   podman load < gnu-hurd-docker.tar
   ```

3. **Migrate volumes** (if needed):
   ```bash
   # Docker volumes are in /var/lib/docker/volumes
   # Podman volumes are in ~/.local/share/containers/storage/volumes
   ```

4. **Use Podman**:
   ```bash
   podman-compose -f compose.yaml -f compose.bind.yaml up -d
   ```

## Best Practices

1. **Use Runtime Abstraction**: The `container-runtime.sh` library abstracts runtime differences
   ```bash
   source scripts/lib/container-runtime.sh
   ```

2. **Explicit Runtime**: Set environment variable when needed
   ```bash
   export CONTAINER_RUNTIME=podman
   ```

3. **Security**: Use rootless when possible
   ```bash
   podman run --security-opt label=disable ...
   ```

4. **Testing**: Test with both runtimes when possible

## Resources

### Documentation
- [Podman Documentation](https://docs.podman.io/)
- [Podman Tutorial](https://github.com/containers/podman/blob/main/docs/tutorials/podman_tutorial.md)
- [Podman Compose](https://github.com/containers/podman-compose)
- [Migration Guide](https://podman.io/getting-started/migration)

### Tools
- [Podman Desktop](https://podman-desktop.io/) - GUI for Podman
- [Buildah](https://buildah.io/) - Build OCI images
- [Skopeo](https://github.com/containers/skopeo) - Inspect and copy images

### Community
- [Podman GitHub](https://github.com/containers/podman)
- [Podman Discussions](https://github.com/containers/podman/discussions)

## Support Matrix

| Feature | Docker | Podman | Notes |
|---------|--------|--------|-------|
| Linux Support | ✅ | ✅ | Both excellent |
| macOS Support | ✅ | ✅ | VM required for both |
| Windows Support | ✅ | ⚠️ | WSL2 recommended |
| BSD Support | ❌ | ✅ | Podman has better BSD support |
| Rootless Mode | ❌ | ✅ | Podman advantage |
| KVM Access | ✅ | ✅ | Both support with proper config |
| Compose Support | ✅ | ✅ | Via podman-compose |
| Kubernetes Pods | ❌ | ✅ | Podman native feature |
| Daemon Required | ✅ | ❌ | Podman advantage |

## Conclusion

Podman provides a compelling alternative to Docker with better security, rootless support, and true daemonless operation. This project fully supports both runtimes through the container runtime abstraction layer in `scripts/lib/container-runtime.sh`.
