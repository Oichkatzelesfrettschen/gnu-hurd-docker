# Deployment Procedures

## Pre-Deployment Checklist

Before deploying the Docker image, verify the following:

- [ ] Docker Engine installed (`docker --version`)
- [ ] Docker Compose installed (`docker-compose --version`)
- [ ] 8GB+ free disk space
- [ ] 2GB+ available RAM
- [ ] QCOW2 image downloaded or available
- [ ] Git repository cloned
- [ ] User has Docker permissions

## Step 1: System Preparation

### Install Docker (if not already installed)

**On CachyOS/Arch Linux:**
```bash
sudo pacman -S docker docker-compose

# Start Docker daemon
sudo systemctl enable --now docker

# Add current user to docker group
sudo usermod -aG docker $USER
newgrp docker

# Verify Docker works
docker ps
```

**On Debian/Ubuntu:**
```bash
sudo apt-get install docker.io docker-compose

# Start Docker daemon
sudo systemctl enable --now docker

# Add user to docker group
sudo usermod -aG docker $USER
newgrp docker
```

### Check System Requirements

```bash
# Verify available disk space (need 8GB+ free)
df -h | grep -E "/$|/home"

# Verify available RAM
free -h

# Check Docker daemon running
docker ps
```

## Step 2: Prepare Repository

### Clone Repository

```bash
# Clone from GitHub
git clone https://github.com/oaich/gnu-hurd-docker.git
cd gnu-hurd-docker

# Or use SSH (if SSH key configured)
git clone git@github.com:oaich/gnu-hurd-docker.git
cd gnu-hurd-docker
```

### Download System Image

The QCOW2 image is not included in the repository (too large).

**Option A: Use provided script**
```bash
./scripts/download-image.sh
# Downloads from: cdimage.debian.org/cdimage/ports/latest/hurd-i386/
```

**Option B: Manual download**
```bash
# Download compressed image (355 MB)
wget https://cdimage.debian.org/cdimage/ports/latest/hurd-i386/debian-hurd.img.tar.xz

# Extract
tar xf debian-hurd.img.tar.xz
# Creates: debian-hurd-i386-20250807.img (4.2 GB)

# Convert to QCOW2 format
qemu-img convert -f raw -O qcow2 debian-hurd-i386-20250807.img debian-hurd-i386-20250807.qcow2
# Creates: debian-hurd-i386-20250807.qcow2 (2.1 GB)
```

**Option C: Use existing image**
```bash
# If you already have the QCOW2 image:
cp /path/to/debian-hurd-i386-20250807.qcow2 ./
```

### Verify Image

```bash
# Check file exists and size is correct
ls -lh debian-hurd-i386-20250807.qcow2
# Should show: 2.1G ... debian-hurd-i386-20250807.qcow2

# Verify QCOW2 format
file debian-hurd-i386-20250807.qcow2
# Should output: QEMU QCOW2 Image
```

## Step 3: Build Docker Image

### Validate Configuration

```bash
# Run validation script (checks Dockerfile, entrypoint, compose)
./scripts/validate-config.sh

# Or manually validate
docker build --dry-run .              # Validate Dockerfile
shellcheck entrypoint.sh              # Validate shell script
python3 -c "import yaml; yaml.safe_load(open('docker-compose.yml'))"  # Validate YAML
```

### Build Image

```bash
# Build Docker image
docker-compose build

# Expected output:
# Step 1/9 : FROM debian:bookworm
# Step 2/9 : RUN apt-get update && apt-get install -y ...
# ...
# Successfully tagged gnu-hurd-dev:latest

# Monitor progress
docker-compose build --progress=plain
```

### Verify Image Built

```bash
# List Docker images
docker image ls | grep gnu-hurd

# Inspect image
docker image inspect gnu-hurd-dev:latest

# Show image size
docker image inspect gnu-hurd-dev:latest --format='{{.Size}}' | awk '{print $1/1024/1024 " MB"}'
```

## Step 4: Deploy Container

### Start Container

```bash
# Start container in background
docker-compose up -d

# Expected output:
# Creating network "gnu-hurd-docker_hurd-net" with driver "bridge"
# Building gnu-hurd-dev
# Successfully tagged gnu-hurd-dev:latest
# Creating gnu-hurd-dev ... done

# Verify container is running
docker-compose ps
# Expected: gnu-hurd-dev  Up (running)
```

### Monitor Container Startup

```bash
# Watch logs in real-time
docker-compose logs -f

# Expected startup sequence:
# [INFO] Starting QEMU GNU/Hurd...
# char device redirected to /dev/pts/X (serial console)
# QEMU boot sequence output
# Login prompt

# Press Ctrl+C to stop watching logs
```

## Step 5: Verify Deployment

### Container Status

```bash
# Check container running
docker-compose ps

# Get detailed container information
docker inspect gnu-hurd-dev

# View resource usage
docker stats gnu-hurd-dev
```

### Access the System

**Via Serial Console:**
```bash
# Find PTY from logs
docker-compose logs | grep "char device redirected"
# Example output: char device redirected to /dev/pts/5

# Connect to serial console
screen /dev/pts/5

# At login prompt, enter:
# Login: root
# Password: (see CREDENTIALS.md)

# Exit screen
Ctrl+A :quit
```

**Via SSH (port 2222):**
```bash
# Connect as root
ssh -p 2222 root@localhost

# Or create key-based authentication
ssh-copy-id -p 2222 root@localhost
ssh -p 2222 root@localhost

# Expected: root@gnu-hurd:~#
```

**Via Docker Shell:**
```bash
# Access bash inside container (for debugging)
docker-compose exec gnu-hurd-dev bash

# Run commands inside container
docker-compose exec gnu-hurd-dev ls /opt/hurd-image/
```

### Network Connectivity

```bash
# From inside container (via SSH/shell)
ping 8.8.8.8              # Test external connectivity
ping google.com           # Test DNS resolution
curl https://google.com   # Test HTTP

# Expected: All should work (network connectivity verified)
```

## Step 6: Post-Deployment Configuration

### Create Standard User Account

```bash
# Access container via SSH or screen
ssh -p 2222 root@localhost

# Inside container, create new user
useradd -m -s /bin/bash -G sudo developer
passwd developer
# Set password when prompted

# Verify user created
id developer
```

### Configure SSH Keys

See [CREDENTIALS.md](CREDENTIALS.md) and [USER-SETUP.md](USER-SETUP.md) for SSH key setup.

### Custom Configuration

```bash
# Example: Install additional packages
ssh -p 2222 root@localhost apt-get update
ssh -p 2222 root@localhost apt-get install -y vim git

# Example: Edit configuration files
scp -P 2222 /path/to/config root@localhost:/etc/
```

## Step 7: Operational Management

### Stop Container

```bash
# Stop running container (saves state)
docker-compose stop

# Restart container
docker-compose start

# Restart container (full restart)
docker-compose restart
```

### Remove Container

```bash
# Stop and remove container
docker-compose down

# Remove container and volumes
docker-compose down -v

# Note: Removes container but preserves disk image
```

### View Logs

```bash
# Show recent logs
docker-compose logs --tail=50

# Show logs from specific time
docker-compose logs --since 5m

# Follow logs in real-time
docker-compose logs -f

# Search logs
docker-compose logs | grep "error"
```

### Container Health Checks

```bash
# QEMU process running?
docker-compose exec gnu-hurd-dev ps aux | grep qemu

# SSH service running?
docker-compose exec gnu-hurd-dev systemctl status ssh

# Disk space usage?
docker-compose exec gnu-hurd-dev df -h

# Network connectivity?
docker-compose exec gnu-hurd-dev ping 8.8.8.8
```

## Troubleshooting Deployment

### Docker Build Fails

```bash
# Clear Docker cache and rebuild
docker-compose build --no-cache

# Check Dockerfile syntax
docker build --dry-run .

# View full build output
docker-compose build --progress=plain

# Check available disk space
df -h
```

### Container Won't Start

```bash
# Check error messages
docker-compose logs --tail=100

# Verify QCOW2 image exists
ls -lh debian-hurd-i386-20250807.qcow2

# Check Docker daemon status
sudo systemctl status docker

# Verify container not already running
docker ps -a | grep gnu-hurd
```

### QEMU Boot Hangs

```bash
# Wait 2-3 minutes (system is booting)
# Press Enter at serial console to proceed past GRUB

# If still stuck, check logs
docker-compose logs | tail -100

# Manual timeout can be increased in entrypoint.sh
```

### SSH Connection Refused

```bash
# Verify SSH service running
docker-compose exec gnu-hurd-dev systemctl status ssh

# Restart SSH
docker-compose exec gnu-hurd-dev systemctl restart ssh

# Check port mapping
docker-compose ps

# Verify SSH accessible on port 2222
nc -zv localhost 2222  # Port open?
```

## Advanced Deployment

### Multiple Instances

```bash
# Create separate compose file for each instance
cp docker-compose.yml docker-compose.prod.yml

# Edit docker-compose.prod.yml
# Change: container_name: gnu-hurd-prod
# Change: ports: "2223:2222" (different port)

# Deploy with specific compose file
docker-compose -f docker-compose.prod.yml up -d
```

### Custom Ports

Edit `docker-compose.yml`:
```yaml
ports:
  - "2222:2222"    # SSH
  - "8080:8080"    # Add HTTP service
  - "3000:3000"    # Add Node.js service

# Rebuild and restart
docker-compose up -d --force-recreate
```

### Resource Limits

Edit `docker-compose.yml`:
```yaml
services:
  gnu-hurd-dev:
    deploy:
      resources:
        limits:
          cpus: '1'           # Limit to 1 CPU
          memory: 2G          # Limit to 2GB RAM
        reservations:
          cpus: '0.5'         # Reserve 0.5 CPU
          memory: 1.5G        # Reserve 1.5GB RAM
```

## Backup and Recovery

### Backup Container

```bash
# Commit running container to image
docker-compose exec gnu-hurd-dev ...  # Stop/finalize system first
docker commit gnu-hurd-dev my-backup:latest

# Save image to file
docker save my-backup:latest | gzip > backup.tar.gz
```

### Restore from Backup

```bash
# Load image from file
gunzip < backup.tar.gz | docker load

# Run from backup
docker run -d --name restore-container my-backup:latest
```

### Backup Disk Image

```bash
# Copy QCOW2 image
cp debian-hurd-i386-20250807.qcow2 debian-hurd-i386-20250807.qcow2.backup

# Create snapshot
qemu-img snapshot -c backup debian-hurd-i386-20250807.qcow2
```

## Production Deployment

For production environments, consider:

1. **Container Registry:** Push image to registry (Docker Hub, etc.)
2. **CI/CD Pipeline:** Automate build and deployment
3. **Monitoring:** Set up logs and metrics collection
4. **Backup Strategy:** Regular backups of disk images
5. **Security:** SSH keys, firewall rules, user management
6. **Updates:** Plan for system updates and security patches

## References

- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [Docker Documentation](https://docs.docker.com/)
- [QEMU Documentation](https://www.qemu.org/documentation/)

---

**Last Updated:** 2025-11-05
**Status:** Complete
