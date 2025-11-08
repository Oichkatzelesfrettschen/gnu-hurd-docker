# CI/CD Guide for Debian GNU/Hurd 2025
**From Ideas to Production**
**Date:** 2025-11-06

---

## Overview

This guide covers setting up complete CI/CD pipelines for Debian GNU/Hurd development, from idea inception to automated deployment.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Best Practices](#best-practices)
3. [GitHub Actions Setup](#github-actions-setup)
4. [Self-Hosted Runners (Hurd)](#self-hosted-runners)
5. [Docker-Based CI](#docker-based-ci)
6. [Package Building](#package-building)
7. [Testing Strategies](#testing-strategies)
8. [Deployment](#deployment)
9. [Example Workflows](#example-workflows)

---

## Architecture Overview

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│              │     │              │     │              │
│  Developer   │────▶│   GitHub     │────▶│    CI/CD     │
│  (Idea)      │     │  Repository  │     │   Pipeline   │
│              │     │              │     │              │
└──────────────┘     └──────────────┘     └──────────────┘
                                                  │
                          ┌───────────────────────┼───────────────────────┐
                          ▼                       ▼                       ▼
                   ┌──────────────┐      ┌──────────────┐       ┌──────────────┐
                   │              │      │              │       │              │
                   │  Build &     │      │   Test in    │       │    Deploy    │
                   │  Package     │      │  Hurd VM     │       │   Release    │
                   │              │      │              │       │              │
                   └──────────────┘      └──────────────┘       └──────────────┘
```

---

## Best Practices

### 1. Repository Structure
```
project/
├── .github/
│   └── workflows/
│       ├── ci.yml              # Main CI workflow
│       ├── build-hurd.yml      # Hurd-specific builds
│       └── release.yml         # Release automation
├── debian/                     # Debian packaging
│   ├── control
│   ├── rules
│   ├── changelog
│   └── compat
├── src/                        # Source code
├── tests/                      # Test suite
├── scripts/                    # Build and automation scripts
├── docs/                       # Documentation
├── Dockerfile.hurd             # Hurd build environment
└── README.md
```

### 2. Branching Strategy
- **main**: Production-ready code
- **develop**: Integration branch
- **feature/***: New features
- **fix/***: Bug fixes
- **release/***: Release preparation

### 3. Commit Messages
Follow Conventional Commits:
```
feat: add Hurd-specific memory allocator
fix: resolve segfault in translator
docs: update build instructions
test: add unit tests for RPC layer
ci: configure GitHub Actions for Hurd
```

---

## GitHub Actions Setup

### Basic CI Workflow

**.github/workflows/ci.yml**
```yaml
name: CI

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  build-hurd:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3

      - name: Build Docker environment
        run: docker-compose build

      - name: Start Hurd VM
        run: |
          docker-compose up -d
          sleep 120  # Wait for Hurd to boot

      - name: Run tests in Hurd
        run: |
          docker exec gnu-hurd-dev bash -c "cd /mnt/host && make test"

      - name: Collect test results
        if: always()
        run: |
          docker cp gnu-hurd-dev:/tmp/test-results.xml ./test-results.xml

      - name: Publish test results
        uses: EnricoMi/publish-unit-test-result-action@v2
        if: always()
        with:
          files: |
            test-results.xml

      - name: Stop Hurd VM
        if: always()
        run: docker-compose down
```

---

## Self-Hosted Runners

### Why Self-Hosted for Hurd?

- GitHub-hosted runners don't support GNU/Hurd
- Need full KVM access for performance
- Custom image management
- Persistent build cache

### Setup Self-Hosted Runner

**On your Linux host (with KVM):**

```bash
# 1. Create runner directory
mkdir -p ~/actions-runner && cd ~/actions-runner

# 2. Download runner
curl -o actions-runner-linux-x64-2.311.0.tar.gz \
  -L https://github.com/actions/runner/releases/download/v2.311.0/actions-runner-linux-x64-2.311.0.tar.gz

# 3. Extract
tar xzf ./actions-runner-linux-x64-2.311.0.tar.gz

# 4. Configure (get token from GitHub repo settings)
./config.sh --url https://github.com/YOUR_ORG/YOUR_REPO \
  --token YOUR_REGISTRATION_TOKEN \
  --labels hurd,i386,kvm

# 5. Install as service
sudo ./svc.sh install
sudo ./svc.sh start
```

**Workflow using self-hosted:**

```yaml
jobs:
  build-hurd:
    runs-on: [self-hosted, hurd, kvm]

    steps:
      - uses: actions/checkout@v4

      - name: Build in Hurd
        run: |
          cd ~/gnu-hurd-docker
          docker-compose up -d
          # ... build steps
```

---

## Docker-Based CI

### Dockerfile for Hurd Build Environment

**Dockerfile.hurd-ci**
```dockerfile
FROM ubuntu:24.04

# Install QEMU and dependencies
RUN apt-get update && apt-get install -y \
    qemu-system-i386 \
    qemu-utils \
    curl \
    git \
    make \
    && rm -rf /var/lib/apt/lists/*

# Copy Hurd image (pre-provisioned)
COPY debian-hurd-provisioned-cli-dev.img /opt/hurd.img

# Copy project files
WORKDIR /workspace
COPY . .

# Entry point for CI
ENTRYPOINT ["./scripts/ci-build-hurd.sh"]
```

**scripts/ci-build-hurd.sh**
```bash
#!/bin/bash
set -e

# Start Hurd VM
qemu-system-i386 \
  -enable-kvm \
  -m 4096 \
  -cpu pentium3 \
  -drive file=/opt/hurd.img,format=raw \
  -netdev user,id=net0,hostfwd=tcp::2222-:22 \
  -device e1000,netdev=net0 \
  -nographic \
  -daemonize

# Wait for SSH
timeout 120 bash -c 'until nc -z localhost 2222; do sleep 2; done'

# Copy code to VM
sshpass -p root scp -P 2222 -r /workspace root@localhost:/tmp/build

# Build inside Hurd
sshpass -p root ssh -p 2222 root@localhost << 'EOF'
cd /tmp/build
./configure
make
make check
make install DESTDIR=/tmp/install
EOF

# Copy artifacts out
sshpass -p root scp -P 2222 -r root@localhost:/tmp/install ./artifacts

# Shutdown
sshpass -p root ssh -p 2222 root@localhost 'shutdown -h now'
```

---

## Package Building

### Debian Package Workflow

**Build .deb package in CI:**

```yaml
jobs:
  package:
    runs-on: [self-hosted, hurd]

    steps:
      - uses: actions/checkout@v4

      - name: Build Debian package
        run: |
          docker exec gnu-hurd-dev bash << 'EOF'
          cd /mnt/host
          dpkg-buildpackage -us -uc -b
          mv ../*.deb /mnt/host/artifacts/
          EOF

      - name: Upload artifacts
        uses: actions/upload-artifact@v4
        with:
          name: hurd-packages
          path: artifacts/*.deb

      - name: Validate package
        run: |
          docker exec gnu-hurd-dev bash << 'EOF'
          cd /mnt/host/artifacts
          for deb in *.deb; do
            dpkg -I "$deb"
            lintian "$deb" || true
          done
          EOF
```

---

## Testing Strategies

### 1. Unit Tests
```bash
# Run inside Hurd VM
make check

# Or with specific test framework
prove -v tests/*.t
python3 -m pytest tests/
```

### 2. Integration Tests
```bash
# Test Hurd-specific features
./tests/test-translators.sh
./tests/test-rpc.sh
./tests/test-memory.sh
```

### 3. System Tests
```bash
# Full system validation
./tests/system-test-suite.sh
```

### Example Test Script

**tests/test-hurd-features.sh**
```bash
#!/bin/bash
set -e

echo "Testing Hurd-specific features..."

# Test translator
settrans -c /tmp/test-translator /hurd/hello
cat /tmp/test-translator

# Test RPC
./tests/rpc-test-client &
./tests/rpc-test-server

# Test memory
./tests/memory-stress-test

echo "All tests passed!"
```

---

## Deployment

### Release Workflow

**.github/workflows/release.yml**
```yaml
name: Release

on:
  push:
    tags:
      - 'v*'

jobs:
  release:
    runs-on: [self-hosted, hurd]

    steps:
      - uses: actions/checkout@v4

      - name: Build release packages
        run: |
          VERSION=${GITHUB_REF#refs/tags/v}
          docker exec gnu-hurd-dev bash << EOF
          cd /mnt/host
          dch -v "$VERSION" -D unstable "Release $VERSION"
          dpkg-buildpackage -us -uc -b
          mv ../*.deb artifacts/
          EOF

      - name: Create checksums
        run: |
          cd artifacts
          sha256sum *.deb > SHA256SUMS
          gpg --detach-sign --armor SHA256SUMS

      - name: Create GitHub release
        uses: softprops/action-gh-release@v1
        with:
          files: |
            artifacts/*.deb
            artifacts/SHA256SUMS
            artifacts/SHA256SUMS.asc
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

      - name: Upload to Debian repository
        run: |
          # Upload to your package repository
          ./scripts/upload-to-repo.sh artifacts/*.deb
```

---

## Example Workflows

### Complete CI/CD Pipeline

```yaml
name: Complete Pipeline

on:
  push:
    branches: [ main, develop ]
    tags: [ 'v*' ]
  pull_request:
    branches: [ main ]

env:
  HURD_IMAGE: debian-hurd-provisioned-cli-dev.img

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Lint code
        run: |
          shellcheck scripts/*.sh
          yamllint .github/workflows/*.yml

  build:
    runs-on: [self-hosted, hurd, kvm]
    needs: lint

    steps:
      - uses: actions/checkout@v4

      - name: Start Hurd environment
        run: |
          cd ~/gnu-hurd-docker
          docker-compose up -d
          timeout 120 bash -c 'until docker exec gnu-hurd-dev test -f /var/run/boot; do sleep 2; done'

      - name: Build project
        run: |
          docker cp . gnu-hurd-dev:/tmp/project
          docker exec gnu-hurd-dev bash << 'EOF'
          cd /tmp/project
          ./configure --prefix=/usr
          make -j$(nproc)
          EOF

      - name: Run tests
        run: |
          docker exec gnu-hurd-dev bash << 'EOF'
          cd /tmp/project
          make check
          make test VERBOSE=1
          EOF

      - name: Build package
        if: startsWith(github.ref, 'refs/tags/')
        run: |
          docker exec gnu-hurd-dev bash << 'EOF'
          cd /tmp/project
          dpkg-buildpackage -us -uc -b
          cp ../*.deb /mnt/host/
          EOF

      - name: Upload artifacts
        if: startsWith(github.ref, 'refs/tags/')
        uses: actions/upload-artifact@v4
        with:
          name: debian-packages
          path: '*.deb'

      - name: Cleanup
        if: always()
        run: docker-compose down

  release:
    if: startsWith(github.ref, 'refs/tags/')
    needs: build
    runs-on: ubuntu-latest

    steps:
      - uses: actions/download-artifact@v4
        with:
          name: debian-packages

      - name: Create release
        uses: softprops/action-gh-release@v1
        with:
          files: '*.deb'
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

---

## Summary

### Key Points

1. **Use Docker + QEMU** for reproducible Hurd builds
2. **Self-hosted runners** for KVM access
3. **Pre-provisioned images** to speed up CI
4. **Debian packaging** for distribution
5. **Comprehensive testing** (unit, integration, system)
6. **Automated releases** with GitHub Actions

### Getting Started Checklist

- [ ] Set up repository structure
- [ ] Configure GitHub Actions workflows
- [ ] Create Hurd Docker environment
- [ ] Set up self-hosted runner (optional)
- [ ] Configure Debian packaging
- [ ] Write test suite
- [ ] Automate release process
- [ ] Document everything

---

**Resources:**
- GitHub Actions: https://docs.github.com/en/actions
- Debian Packaging: https://www.debian.org/doc/manuals/maint-guide/
- GNU/Hurd Docs: https://www.gnu.org/software/hurd/

**Repository:** gnu-hurd-docker
**Generated:** 2025-11-06
