# CI/CD Documentation

**Last Updated**: 2025-11-07
**Section**: 05-CI-CD
**Purpose**: Continuous Integration and Continuous Deployment workflows

---

## Overview

This section covers CI/CD automation for GNU/Hurd x86_64 Docker environments, including GitHub Actions workflows, pre-provisioned images, and automated testing strategies.

**Audience**: DevOps engineers, CI/CD maintainers, automation developers

**Prerequisites**: Understanding of Docker, GitHub Actions, QEMU

---

## Documents in This Section

### [SETUP.md](SETUP.md)
**CI/CD environment setup and configuration**

- GitHub Actions environment
- Self-hosted runners (KVM acceleration)
- Docker in CI
- QEMU in CI (TCG fallback)
- Secrets management
- Artifact caching
- Pre-provisioned image usage

**When to use**: Set up new CI/CD pipeline, configure GitHub Actions

---

### [WORKFLOWS.md](WORKFLOWS.md)
**Advanced workflow patterns and automation**

- QMP (QEMU Machine Protocol) automation
- Matrix testing (RAM/CPU/acceleration combinations)
- Conditional workflows (KVM vs TCG)
- Artifact caching strategies
- Serial console automation
- Multi-stage testing (build → test → release)
- Performance optimization patterns

**When to use**: Design complex workflows, optimize CI performance

---

### [PROVISIONED-IMAGE.md](PROVISIONED-IMAGE.md)
**Pre-provisioned image creation and usage**

- Why pre-provision (85% faster, 95% reliable)
- Provisioning tiers (Essential, Development, GUI)
- Creating provisioned images
- Using provisioned images in CI
- Maintenance and updates
- Storage and distribution

**When to use**: Speed up CI, improve reliability, reduce setup time

---

## CI/CD Quick Start

### GitHub Actions Workflow (Basic)

**File**: `.github/workflows/build-x86_64.yml`

```yaml
name: Build and Test Hurd x86_64

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    timeout-minutes: 30

    steps:
      - uses: actions/checkout@v4

      - name: Download Hurd image
        run: ./scripts/setup-hurd-amd64.sh

      - name: Build Docker image
        run: docker build -t hurd-test .

      - name: Start container
        run: docker-compose up -d

      - name: Wait for SSH
        run: |
          for i in {1..60}; do
            if ssh -o StrictHostKeyChecking=no -p 2222 root@localhost true 2>/dev/null; then
              echo "SSH ready"
              exit 0
            fi
            sleep 5
          done
          exit 1

      - name: Run tests
        run: ./scripts/test-hurd-system.sh

      - name: Cleanup
        if: always()
        run: docker-compose down
```

**Time**: 10-15 minutes (TCG on GitHub runners)
**Success rate**: 80-90%

---

### Pre-Provisioned Image Workflow (Recommended)

**Why**: 85% faster, 95% reliability vs serial automation

**File**: `.github/workflows/build-provisioned.yml`

```yaml
name: Build with Pre-Provisioned Image

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    timeout-minutes: 15

    steps:
      - uses: actions/checkout@v4

      - name: Download pre-provisioned image
        run: |
          curl -L -o debian-hurd-amd64-provisioned.qcow2.xz \
            https://example.com/hurd-provisioned.qcow2.xz
          unxz debian-hurd-amd64-provisioned.qcow2.xz

      - name: Start container
        run: docker-compose up -d

      - name: Test SSH (should be immediate)
        run: ssh -p 2222 root@localhost uname -a

      - name: Run tests
        run: ./scripts/test-hurd-system.sh
```

**Time**: 2-5 minutes (no provisioning needed)
**Success rate**: 95%+

---

## Quick Navigation

**Getting Started**:
- [Installation](../01-GETTING-STARTED/INSTALLATION.md)
- [Quickstart](../01-GETTING-STARTED/QUICKSTART.md)

**Architecture** (understand before CI/CD):
- [System Design](../02-ARCHITECTURE/SYSTEM-DESIGN.md)
- [QEMU Configuration](../02-ARCHITECTURE/QEMU-CONFIGURATION.md)
- [Control Plane](../02-ARCHITECTURE/CONTROL-PLANE.md)

**Operation**:
- [Snapshots](../04-OPERATION/SNAPSHOTS.md) - Create provisioned images
- [Monitoring](../04-OPERATION/MONITORING.md) - CI performance

**Reference**:
- [Scripts](../08-REFERENCE/SCRIPTS.md) - Automation tools
- [Credentials](../08-REFERENCE/CREDENTIALS.md) - CI secrets

---

## CI/CD Strategy

### Traditional Approach (Deprecated)

**Workflow**:
1. Download vanilla Debian Hurd image
2. Boot QEMU
3. Wait for serial console
4. Install SSH via expect automation
5. Configure users
6. Install packages
7. Run tests

**Problems**:
- **Time**: 20-40 minutes
- **Reliability**: 60-70% (serial automation fragile)
- **Complexity**: Expect scripts brittle

---

### Pre-Provisioned Approach (Recommended)

**Workflow**:
1. Download pre-provisioned image
2. Boot QEMU
3. SSH immediately (already configured)
4. Run tests

**Benefits**:
- **Time**: 2-5 minutes (85% faster)
- **Reliability**: 95%+ (no serial automation)
- **Simplicity**: No fragile automation

**See**: [PROVISIONED-IMAGE.md](PROVISIONED-IMAGE.md)

---

## Performance Benchmarks

### GitHub Actions (TCG)

| Stage | Time (Traditional) | Time (Provisioned) | Speedup |
|-------|-------------------|-------------------|---------|
| Download | 2 min | 2 min | - |
| Boot | 3 min | 3 min | - |
| SSH Setup | 10-20 min | 0 sec | ∞ |
| Tests | 5 min | 5 min | - |
| **Total** | **20-30 min** | **10 min** | **2-3x** |

### Self-Hosted Runner (KVM)

| Stage | Time (Traditional) | Time (Provisioned) | Speedup |
|-------|-------------------|-------------------|---------|
| Download | 1 min | 1 min | - |
| Boot | 30 sec | 30 sec | - |
| SSH Setup | 5-10 min | 0 sec | ∞ |
| Tests | 2 min | 2 min | - |
| **Total** | **8-14 min** | **3.5 min** | **2-4x** |

---

## Common CI/CD Patterns

### Pattern 1: Matrix Testing

Test multiple configurations in parallel:

```yaml
strategy:
  matrix:
    ram: [2048, 4096, 8192]
    smp: [1, 2, 4]
    accel: [tcg, kvm]
    exclude:
      - accel: kvm  # No KVM on GitHub runners
```

**Use case**: Verify compatibility across configurations

---

### Pattern 2: Conditional Workflows

Run different steps based on environment:

```yaml
- name: Detect acceleration
  id: accel
  run: |
    if [ -e /dev/kvm ]; then
      echo "kvm=true" >> $GITHUB_OUTPUT
    else
      echo "kvm=false" >> $GITHUB_OUTPUT
    fi

- name: Fast boot (KVM)
  if: steps.accel.outputs.kvm == 'true'
  run: QEMU_ACCEL="-accel kvm" docker-compose up -d

- name: Slow boot (TCG)
  if: steps.accel.outputs.kvm != 'true'
  run: QEMU_ACCEL="-accel tcg" docker-compose up -d
```

**Use case**: Optimize for KVM when available

---

### Pattern 3: Artifact Caching

Cache images between runs:

```yaml
- name: Cache Hurd image
  uses: actions/cache@v3
  with:
    path: debian-hurd-amd64-*.qcow2
    key: hurd-image-${{ hashFiles('scripts/download-image.sh') }}
```

**Use case**: Speed up subsequent runs

---

## Troubleshooting CI/CD

**Workflow times out**:
- Increase `timeout-minutes` (default: 15 → 30)
- Use pre-provisioned image (faster)

**SSH connection fails**:
- Check wait loop timeout (increase iterations)
- Verify port forwarding in docker-compose.yml
- See [SSH Issues](../06-TROUBLESHOOTING/SSH-ISSUES.md)

**Serial automation fails**:
- **Don't use serial automation in CI**
- Use pre-provisioned images instead
- Serial automation is fragile (60-70% success rate)

**QEMU won't start**:
- Check KVM availability (`ls /dev/kvm`)
- Use TCG fallback
- Verify QCOW2 image downloaded correctly

---

## Best Practices

1. **Use pre-provisioned images** (not serial automation)
2. **Cache artifacts** (images, packages)
3. **Fail fast** (detect errors early in workflow)
4. **Timeout generously** (TCG is slow)
5. **Upload logs on failure** (for debugging)
6. **Test incrementally** (don't run everything in one job)

---

## For DevOps Engineers

**CI/CD Architecture**:
- [SETUP.md](SETUP.md) - Environment configuration
- [WORKFLOWS.md](WORKFLOWS.md) - Advanced patterns
- [PROVISIONED-IMAGE.md](PROVISIONED-IMAGE.md) - Image strategy

**Performance Optimization**:
- Use KVM (self-hosted runners)
- Cache images and artifacts
- Pre-provision instead of automate

**Reliability**:
- Pre-provisioned images: 95%+
- Serial automation: 60-70%
- **Recommendation**: Always use pre-provisioned

---

[← Back to Documentation Index](../INDEX.md)
