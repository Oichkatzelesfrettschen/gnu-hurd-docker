# GNU/Hurd Docker - Simplest Possible Start

**TL;DR:** Just use Docker, no cloning or building required.

---

## Method 1: Docker Pull (Recommended - 3 commands)

```bash
# 1. Pull the pre-built image from GitHub Container Registry
docker pull ghcr.io/oichkatzelesfrettschen/gnu-hurd-docker:latest

# 2. Download Debian Hurd QCOW2 image (~355 MB download, ~2 GB extracted)
wget https://cdimage.debian.org/cdimage/ports/latest/hurd-i386/debian-hurd.img.tar.xz
tar xf debian-hurd.img.tar.xz
mv debian-hurd.img debian-hurd-i386-20250807.qcow2

# 3. Run it
docker run -d --privileged \
  --name gnu-hurd \
  -p 2222:2222 -p 5555:5555 -p 5901:5901 \
  -v $(pwd):/opt/hurd-image \
  --device /dev/kvm \
  ghcr.io/oichkatzelesfrettschen/gnu-hurd-docker:latest
```

**That's it.** Wait 2-3 minutes for boot, then SSH:

```bash
ssh -p 2222 root@localhost
# Default password: (varies by Debian Hurd release, try no password or "root")
```

---

## Method 2: Docker Run (One-liner - if you already have the QCOW2)

```bash
docker run -d --privileged \
  --name gnu-hurd \
  -p 2222:2222 -p 5555:5555 -p 5901:5901 \
  -v /path/to/your/hurd/image:/opt/hurd-image \
  --device /dev/kvm \
  ghcr.io/oichkatzelesfrettschen/gnu-hurd-docker:latest
```

Replace `/path/to/your/hurd/image` with the directory containing `debian-hurd-i386-20250807.qcow2`.

---

## Method 3: Docker Compose (If you want declarative config)

Create `docker-compose.yml`:

```yaml
services:
  gnu-hurd-dev:
    image: ghcr.io/oichkatzelesfrettschen/gnu-hurd-docker:latest
    container_name: gnu-hurd-dev
    privileged: true

    volumes:
      - .:/opt/hurd-image

    ports:
      - "2222:2222"
      - "5555:5555"
      - "5901:5901"

    devices:
      - /dev/kvm

    environment:
      - QEMU_RAM=2048
      - DISPLAY_MODE=nographic
```

Then:

```bash
docker-compose up -d
```

---

## Access Methods

### SSH (Primary)
```bash
ssh -p 2222 root@localhost
```

### Serial Console (Boot debugging)
```bash
telnet localhost 5555
```

### VNC (If DISPLAY_MODE=vnc)
```bash
# Connect VNC client to localhost:5901
```

### Container Logs
```bash
docker logs -f gnu-hurd
```

---

## Why This Is Better

**Old way (README):**
```bash
git clone https://github.com/oaich/gnu-hurd-docker.git  # ← Unnecessary
cd gnu-hurd-docker                                      # ← Unnecessary
./scripts/download-image.sh                             # ← OK, but can be manual
docker-compose build                                     # ← Unnecessary (takes time)
docker-compose up -d                                     # ← Finally running
```

**New way (this guide):**
```bash
docker pull ghcr.io/oichkatzelesfrettschen/gnu-hurd-docker:latest
wget ... && tar ...
docker run ...
```

**Benefits:**
- ✅ No git clone required
- ✅ No build step (pre-built image from CI/CD)
- ✅ Faster (pull cached layers vs build from scratch)
- ✅ Works anywhere Docker runs
- ✅ Always get latest tested image

---

## Troubleshooting

**"Cannot find QCOW2 image"**
```bash
# Make sure debian-hurd-i386-20250807.qcow2 is in current directory
ls -lh *.qcow2
```

**"Cannot access /dev/kvm"**
```bash
# Remove --device /dev/kvm (uses slower TCG emulation instead)
docker run -d --privileged \
  --name gnu-hurd \
  -p 2222:2222 \
  -v $(pwd):/opt/hurd-image \
  ghcr.io/oichkatzelesfrettschen/gnu-hurd-docker:latest
```

**"Image not found on GHCR"**
```bash
# Image will be available after next git push triggers CI/CD
# For now, use Method 4 below (build locally)
```

---

## Method 4: Build Locally (Only if GHCR image unavailable)

```bash
git clone https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker.git
cd gnu-hurd-docker
docker-compose build
docker-compose up -d
```

This is the fallback if GHCR hasn't published the image yet.

---

## Next Steps

Once connected via SSH:

```bash
# Mount shared scripts (if using volumes)
mkdir -p /mnt/scripts
mount -t 9p -o trans=virtio scripts /mnt/scripts

# Install development tools
cd /mnt/scripts
./setup-hurd-dev.sh

# Configure users
./configure-users.sh

# Setup bash environment
./configure-shell.sh
```

---

## Full Documentation

For advanced usage, see:
- **README.md** - Complete documentation
- **docs/** - Technical guides
- **scripts/** - Utility scripts

---

**Status:** Ready to use
**Image:** `ghcr.io/oichkatzelesfrettschen/gnu-hurd-docker:latest`
**Size:** ~500 MB (compressed layers)
**Platform:** Linux (KVM recommended), macOS/Windows (TCG fallback)
