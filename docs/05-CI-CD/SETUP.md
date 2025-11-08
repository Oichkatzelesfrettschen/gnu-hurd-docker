# GNU/Hurd Docker - CI/CD Setup Guide

**Last Updated**: 2025-11-07
**Consolidated From**:
- CI-CD-GUIDE-HURD.md (general CI/CD guide)
- QUICKSTART-CI-SETUP.md (quick setup)
- CI-CD-MIGRATION-SUMMARY.md (migration notes)

**Purpose**: Complete guide for setting up CI/CD for Debian GNU/Hurd development

**Scope**: Debian GNU/Hurd x86_64 only (i386 deprecated 2025-11-07)

---

## Overview

This guide covers two production-grade CI/CD strategies for GNU/Hurd:

### Strategy 1: Pre-Provisioned Images (Recommended)

**Concept**: Create a fully-configured Hurd image locally, upload to GitHub Releases, download in CI

**Benefits**:
- ✅ Fast CI runs (3-5 minutes)
- ✅ Reliable (95%+ success rate)
- ✅ No serial console automation
- ✅ Pre-installed SSH and tools
- ✅ Simple workflow

**Trade-offs**:
- Requires initial image creation (one-time)
- Image updates need new uploads
- Storage space for releases (~1-2 GB compressed)

### Strategy 2: Runtime Provisioning (Advanced)

**Concept**: Provision fresh Hurd image in each CI run using QMP automation

**Benefits**:
- ✅ Always fresh environment
- ✅ No pre-built artifacts needed
- ✅ Reproducible from scratch

**Trade-offs**:
- Slower CI runs (10-15 minutes)
- More complex automation
- Lower success rate (80-90%)

**Recommendation**: Start with Strategy 1, move to Strategy 2 only if you need pristine environments every run.

---

## Quick Start (Pre-Provisioned Image)

### Prerequisites

- Linux host with KVM support (or Docker Desktop on macOS/Windows)
- GitHub repository with Actions enabled
- `gh` CLI tool installed
- Docker and docker-compose installed

### Step 1: Create Pre-Provisioned Image

```bash
# Clone repository
git clone https://github.com/YOUR_USERNAME/gnu-hurd-docker.git
cd gnu-hurd-docker

# Download Debian GNU/Hurd x86_64 image
./scripts/download-image.sh

# Start Hurd VM and provision it
docker-compose up -d

# Wait for boot (5-10 minutes)
sleep 600

# SSH in and install essentials
ssh -p 2222 root@localhost
# Inside guest:
apt-get update
apt-get install -y openssh-server curl wget git gcc make cmake
systemctl enable ssh
exit

# Shutdown gracefully
ssh -p 2222 root@localhost 'shutdown -h now'
sleep 30
docker-compose down

# Copy provisioned image
cp debian-hurd-amd64-20250807.qcow2 debian-hurd-amd64-provisioned.qcow2
```

### Step 2: Compress and Upload

```bash
# Compress image
tar czf debian-hurd-amd64-provisioned.qcow2.tar.gz \
    debian-hurd-amd64-provisioned.qcow2

# Generate checksum
sha256sum debian-hurd-amd64-provisioned.qcow2.tar.gz | \
    tee debian-hurd-amd64-provisioned.qcow2.tar.gz.sha256

# Upload to GitHub Release
gh release create v1.0.0-provisioned \
    debian-hurd-amd64-provisioned.qcow2.tar.gz \
    debian-hurd-amd64-provisioned.qcow2.tar.gz.sha256 \
    --title "Pre-Provisioned Debian GNU/Hurd x86_64 Image" \
    --notes "SSH enabled, dev tools installed, ready for CI/CD"
```

### Step 3: Create CI Workflow

Create `.github/workflows/test-hurd.yml`:

```yaml
name: Test GNU/Hurd

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]
  workflow_dispatch:

env:
  PROVISIONED_IMAGE_URL: "https://github.com/YOUR_USERNAME/gnu-hurd-docker/releases/download/v1.0.0-provisioned/debian-hurd-amd64-provisioned.qcow2.tar.gz"
  PROVISIONED_IMAGE_SHA256: "paste_sha256_here"

jobs:
  test:
    runs-on: ubuntu-latest
    timeout-minutes: 30

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3

      - name: Download provisioned image
        run: |
          curl -L "$PROVISIONED_IMAGE_URL" -o provisioned.tar.gz
          echo "$PROVISIONED_IMAGE_SHA256  provisioned.tar.gz" | sha256sum -c
          tar xzf provisioned.tar.gz

      - name: Start Hurd VM
        run: |
          # Move image to expected location
          mkdir -p images
          mv debian-hurd-amd64-provisioned.qcow2 debian-hurd-amd64-20250807.qcow2

          # Build and start
          docker-compose build
          docker-compose up -d

      - name: Wait for system
        run: |
          for i in {1..60}; do
            if ssh -o StrictHostKeyChecking=no -p 2222 root@localhost true 2>/dev/null; then
              echo "SSH ready"
              exit 0
            fi
            sleep 5
          done
          echo "SSH timeout"
          exit 1

      - name: Verify architecture
        run: |
          ssh -o StrictHostKeyChecking=no -p 2222 root@localhost << 'EOF'
          uname -a
          dpkg --print-architecture
          gcc --version
          EOF

      - name: Run tests
        run: |
          # Copy test files
          docker cp ./tests gnu-hurd-x86_64:/tmp/

          # Run tests
          ssh -o StrictHostKeyChecking=no -p 2222 root@localhost << 'EOF'
          cd /tmp/tests
          bash run-all-tests.sh
          EOF

      - name: Collect results
        if: always()
        run: |
          docker cp gnu-hurd-x86_64:/tmp/test-results.xml ./
          docker-compose logs > docker-logs.txt

      - name: Upload artifacts
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: test-results
          path: |
            test-results.xml
            docker-logs.txt

      - name: Cleanup
        if: always()
        run: docker-compose down
```

### Step 4: Push and Test

```bash
# Update workflow with your GitHub username and SHA256
sed -i 's/YOUR_USERNAME/your-actual-username/g' .github/workflows/test-hurd.yml
sed -i "s/paste_sha256_here/$(cat debian-hurd-amd64-provisioned.qcow2.tar.gz.sha256 | cut -d' ' -f1)/" .github/workflows/test-hurd.yml

# Commit and push
git add .github/workflows/test-hurd.yml
git commit -m "CI/CD: Add test workflow with pre-provisioned x86_64 image"
git push

# Watch CI run
gh run watch
```

---

## Architecture Comparison

| Aspect | x86_64 (Current) | i386 (Deprecated) |
|--------|------------------|-------------------|
| QEMU Binary | `qemu-system-x86_64` | `qemu-system-i386` |
| Image | `debian-hurd-amd64-*.qcow2` | `debian-hurd-i386-*.img` |
| CPU | `-cpu host` or `-cpu max` | `-cpu pentium3` |
| RAM | 4 GB default | 1.5-2 GB typical |
| SMP | 2 cores (stable) | 1 core (safer) |
| Boot Time | 5-10 min (TCG) | 10-15 min (TCG) |
| Performance | Moderate (less optimized) | Better (more mature) |
| Future | ✅ Recommended | ❌ Deprecated |

---

## Repository Structure for CI/CD

```
project/
├── .github/
│   └── workflows/
│       ├── test-hurd.yml          # Main CI workflow
│       ├── build-release.yml      # Release builds
│       └── validate.yml           # Linting/validation
├── tests/
│   ├── run-all-tests.sh           # Test orchestrator
│   ├── unit/                      # Unit tests
│   ├── integration/               # Integration tests
│   └── system/                    # System-level tests
├── scripts/
│   ├── download-image.sh          # Download Hurd image
│   ├── provision-image.sh         # Provision image script
│   └── ci-build-hurd.sh           # CI build automation
├── docker-compose.yml             # Docker environment
└── Dockerfile                     # Container definition
```

---

## Best Practices

### 1. Timeout Management

```yaml
jobs:
  test:
    timeout-minutes: 30  # Job-level timeout

    steps:
      - name: Wait for boot
        timeout-minutes: 10  # Step-level timeout
        run: |
          # Wait with max iterations
          for i in {1..120}; do
            # Check condition
            sleep 5
          done
```

### 2. Resource Cleanup

```yaml
- name: Cleanup QEMU
  if: always()  # Always run
  run: |
    docker-compose down || true
    docker system prune -f || true
```

### 3. Caching

```yaml
- name: Cache QEMU images
  uses: actions/cache@v3
  with:
    path: images/
    key: hurd-x86_64-${{ hashFiles('scripts/download-image.sh') }}
```

### 4. Artifact Collection

```yaml
- name: Collect logs
  if: always()
  run: |
    docker-compose logs > docker-logs.txt
    tar czf logs.tar.gz *.log *.txt

- name: Upload artifacts
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: debug-logs
    path: logs.tar.gz
    retention-days: 7
```

### 5. Matrix Testing

```yaml
strategy:
  matrix:
    memory: [2048, 4096, 8192]
    smp: [1, 2, 4]
steps:
  - name: Test with ${{ matrix.memory }}MB RAM
    run: |
      QEMU_RAM=${{ matrix.memory }} QEMU_SMP=${{ matrix.smp }} \
        docker-compose up -d
```

---

## Self-Hosted Runners (KVM Acceleration)

### Why Self-Hosted?

GitHub-hosted runners don't have KVM access, resulting in:
- Slow boot times (10-20 minutes)
- Poor performance (10-20% of native)
- TCG software emulation only

Self-hosted runners with KVM provide:
- Fast boot times (2-5 minutes)
- Good performance (80-90% of native)
- Hardware virtualization
- Persistent build cache

### Setup Self-Hosted Runner

**On Linux host with KVM:**

```bash
# 1. Create runner directory
mkdir -p ~/actions-runner && cd ~/actions-runner

# 2. Download runner
curl -o actions-runner-linux-x64.tar.gz -L \
  https://github.com/actions/runner/releases/download/v2.311.0/actions-runner-linux-x64-2.311.0.tar.gz

# 3. Extract
tar xzf actions-runner-linux-x64.tar.gz

# 4. Configure (get token from repo settings → Actions → Runners)
./config.sh \
  --url https://github.com/YOUR_USERNAME/YOUR_REPO \
  --token YOUR_REGISTRATION_TOKEN \
  --labels self-hosted,linux,x64,kvm,hurd

# 5. Install as service
sudo ./svc.sh install
sudo ./svc.sh start

# 6. Verify
sudo ./svc.sh status
```

**Add to runner group (optional):**
```bash
# Ensure runner user is in kvm and docker groups
sudo usermod -aG kvm,docker github-runner
```

**Workflow using self-hosted runner:**

```yaml
jobs:
  test-kvm:
    runs-on: [self-hosted, kvm, hurd]

    steps:
      - uses: actions/checkout@v4

      - name: Start Hurd with KVM
        run: |
          docker-compose build
          docker-compose up -d
```

### Performance Comparison

| Metric | GitHub-Hosted (TCG) | Self-Hosted (KVM) |
|--------|---------------------|-------------------|
| Boot Time | 10-15 min | 2-5 min |
| CPU Performance | 10-20% native | 80-90% native |
| Memory Overhead | High | Low |
| I/O Speed | Moderate | Fast |
| Cost | Free (public repos) | Infrastructure cost |
| Availability | Always | Requires setup |

---

## Troubleshooting CI/CD

### Common Issues

**Problem: "Image download fails"**

```yaml
# Solution: Verify URL and add retries
- name: Download with retries
  run: |
    for i in {1..3}; do
      curl -L "$PROVISIONED_IMAGE_URL" -o provisioned.tar.gz && break
      sleep 10
    done
    echo "$PROVISIONED_IMAGE_SHA256  provisioned.tar.gz" | sha256sum -c
```

**Problem: "SSH connection timeout"**

```yaml
# Solution: Increase wait time and add debug
- name: Wait for SSH with debug
  run: |
    for i in {1..120}; do
      echo "Attempt $i/120"
      if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
           -p 2222 root@localhost true 2>/dev/null; then
        echo "SSH ready"
        exit 0
      fi
      # Check if QEMU is running
      docker-compose ps
      # Check logs
      docker-compose logs --tail=20
      sleep 5
    done
    echo "SSH timeout after 10 minutes"
    docker-compose logs
    exit 1
```

**Problem: "QEMU won't start"**

```bash
# Check QEMU syntax
docker-compose config

# Verify image exists
ls -lh debian-hurd-amd64-20250807.qcow2

# Check image integrity
qemu-img check debian-hurd-amd64-20250807.qcow2

# Test locally
docker-compose up
```

**Problem: "Out of disk space"**

```yaml
# Solution: Clean up before build
- name: Free disk space
  run: |
    docker system prune -af
    sudo apt-get clean
    df -h
```

---

## Security Considerations

### SSH Keys

```yaml
# Generate unique keys per repository
- name: Setup SSH key
  run: |
    mkdir -p ~/.ssh
    echo "${{ secrets.HURD_SSH_PRIVATE_KEY }}" > ~/.ssh/hurd_key
    chmod 600 ~/.ssh/hurd_key
    ssh-keyscan -p 2222 localhost >> ~/.ssh/known_hosts
```

**Store in GitHub Secrets:**
1. Go to repo Settings → Secrets and variables → Actions
2. Add `HURD_SSH_PRIVATE_KEY` (private key content)
3. Add `HURD_SSH_PUBLIC_KEY` (public key content)

### Image Integrity

```yaml
# Always verify checksums
- name: Verify image
  run: |
    echo "$PROVISIONED_IMAGE_SHA256  provisioned.tar.gz" | sha256sum -c
```

### Secrets Management

```yaml
# Never echo secrets
- name: Use secrets safely
  run: |
    # DON'T: echo "${{ secrets.PASSWORD }}"
    # DO: pass via environment
    export PASSWORD="${{ secrets.PASSWORD }}"
    ./script-that-uses-password.sh
```

---

## Next Steps

- **Read Workflow Patterns**: See `WORKFLOWS.md` for advanced patterns
- **Pre-Provisioned Images**: See `PROVISIONED-IMAGE.md` for automation
- **Troubleshooting**: See `../06-TROUBLESHOOTING/` for common issues

---

**Status**: Production Ready (x86_64-only)
**Last Updated**: 2025-11-07
**Architecture**: Pure x86_64
