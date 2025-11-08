# GNU/Hurd Docker - CI/CD Workflow Patterns

**Last Updated**: 2025-11-07
**Consolidated From**:
- CI-CD-GUIDE.md (workflow examples)
- .github/workflows/*.yml (actual workflows)
- QMP automation documentation

**Purpose**: Advanced CI/CD workflow patterns and automation for GNU/Hurd

**Scope**: Debian GNU/Hurd x86_64 only (i386 deprecated 2025-11-07)

---

## Overview

This guide covers advanced GitHub Actions workflows, QMP automation, and CI/CD patterns specifically designed for GNU/Hurd development.

**Workflow Categories**:
1. **Validation** - Lint, test, verify configurations
2. **Build** - Build Docker images, QEMU images, packages
3. **Test** - Unit, integration, system tests
4. **Release** - Publish artifacts, create releases
5. **Deploy** - Documentation, containers, packages

---

## Current Workflows

### 1. build-x86_64.yml - Hurd Image Build

**Purpose**: Build and test Debian GNU/Hurd x86_64 image

**Triggers**:
- Push to `main`
- Manual dispatch

**Key Steps**:
```yaml
- Download x86_64 image (setup-hurd-amd64.sh)
- Build Docker image
- Start VM with TCG fallback
- Test SSH connectivity
- Upload image artifact
```

**Performance**:
- Duration: 10-15 minutes (TCG on GitHub runners)
- Success rate: 80-90% (SSH may timeout)

**Usage**:
```bash
# Trigger manually
gh workflow run build-x86_64.yml

# Watch progress
gh run watch
```

### 2. validate.yml - Configuration Validation

**Purpose**: Validate Dockerfile, scripts, and configs

**Triggers**:
- Push/PR affecting Dockerfile, entrypoint.sh, docker-compose.yml

**Checks**:
- Dockerfile structure
- ShellCheck on all .sh scripts
- YAML syntax validation
- File permissions

**Example Output**:
```
✓ Dockerfile structure is present
✓ entrypoint.sh passes shellcheck validation
✓ docker-compose.yml has valid YAML syntax
✓ All scripts are executable
```

### 3. push-ghcr.yml - Container Registry Publishing

**Purpose**: Build and push Docker images to GitHub Container Registry

**Triggers**:
- Push to `main`
- Tags matching `v*`
- Manual dispatch

**Features**:
- Multi-platform support (future)
- Automatic tagging (branch, semver, SHA)
- Image attestation and signatures

**Image Tags**:
```
ghcr.io/owner/gnu-hurd-docker:latest         # main branch
ghcr.io/owner/gnu-hurd-docker:v1.0.0         # version tag
ghcr.io/owner/gnu-hurd-docker:pr-123         # PR preview
ghcr.io/owner/gnu-hurd-docker:sha-abc1234    # Commit SHA
```

### 4. validate-config.yml - Extended Validation

**Purpose**: Validate shell scripts with shellcheck

**Scope**: All `.sh` files in repository

### 5. release.yml - Release Automation

**Purpose**: Create GitHub releases with artifacts

**Triggers**: Tags matching `v*`

### 6. deploy-pages.yml - Documentation Deployment

**Purpose**: Deploy docs to GitHub Pages

### 7. quality-and-security.yml - Security Scanning

**Purpose**: Security and quality checks

### 8. release-artifacts.yml - Artifact Packaging

**Purpose**: Package and upload release artifacts

---

## QMP Automation for CI/CD

### QMP (QEMU Machine Protocol)

QMP provides programmatic control of QEMU for CI automation.

**Benefits**:
- JSON-based (machine-readable)
- Synchronous command execution
- VM state query and control
- Event notifications

**Use Cases**:
- Wait for boot completion
- Send keyboard input
- Take screenshots
- Query VM status
- Graceful shutdown

### QMP Socket Setup

**QEMU Configuration**:
```bash
qemu-system-x86_64 \
    ... \
    -qmp unix:/tmp/qmp.sock,server=on,wait=off
```

**docker-compose.yml**:
```yaml
services:
  hurd-x86_64:
    volumes:
      - qmp-sockets:/tmp/qmp

volumes:
  qmp-sockets:
```

### QMP Helper Script

**Create scripts/qmp-helper.py**:
```python
#!/usr/bin/env python3
"""QMP helper for CI automation"""
import json, socket, sys, os

def qmp_connect(sock_path):
    """Connect and negotiate capabilities"""
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(sock_path)

    # Read greeting
    greeting = s.recv(4096)

    # Negotiate capabilities
    s.sendall(b'{"execute":"qmp_capabilities"}\n')
    s.recv(4096)

    return s

def qmp_command(sock, cmd):
    """Execute QMP command"""
    sock.sendall((json.dumps(cmd) + "\n").encode())
    response = sock.recv(65536).decode()
    return json.loads(response)

if __name__ == "__main__":
    sock_path = os.getenv("QMP_SOCKET", "/tmp/qmp.sock")

    s = qmp_connect(sock_path)

    # Read command from stdin
    cmd = json.load(sys.stdin)

    # Execute
    result = qmp_command(s, cmd)

    # Output result
    print(json.dumps(result, indent=2))

    s.close()
```

### QMP Usage in Workflows

**Query VM Status**:
```yaml
- name: Check VM status
  run: |
    echo '{"execute":"query-status"}' | \
      docker exec -i hurd-x86_64 python3 /scripts/qmp-helper.py
```

**Send Keyboard Input**:
```yaml
- name: Send Enter key
  run: |
    echo '{"execute":"human-monitor-command","arguments":{"command-line":"sendkey ret"}}' | \
      docker exec -i hurd-x86_64 python3 /scripts/qmp-helper.py
```

**Graceful Shutdown**:
```yaml
- name: Shutdown VM
  run: |
    echo '{"execute":"system_powerdown"}' | \
      docker exec -i hurd-x86_64 python3 /scripts/qmp-helper.py
```

---

## Advanced Workflow Patterns

### Pattern 1: Matrix Testing

Test multiple configurations in parallel:

```yaml
strategy:
  matrix:
    ram: [2048, 4096, 8192]
    smp: [1, 2, 4]
    accel: [tcg, kvm]
    exclude:
      # No KVM on GitHub runners
      - accel: kvm

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Test ${{ matrix.ram }}MB / ${{ matrix.smp }} CPU / ${{ matrix.accel }}
        env:
          QEMU_RAM: ${{ matrix.ram }}
          QEMU_SMP: ${{ matrix.smp }}
          QEMU_ACCEL: ${{ matrix.accel }}
        run: docker-compose up -d
```

### Pattern 2: Conditional Workflows

Run different steps based on conditions:

```yaml
jobs:
  test:
    steps:
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
        run: |
          QEMU_ARGS="-enable-kvm -cpu host" docker-compose up -d

      - name: Slow boot (TCG)
        if: steps.accel.outputs.kvm != 'true'
        run: |
          QEMU_ARGS="-cpu max" docker-compose up -d
```

### Pattern 3: Artifact Caching

Cache images between runs:

```yaml
- name: Cache Hurd image
  uses: actions/cache@v3
  with:
    path: |
      debian-hurd-amd64-*.qcow2
    key: hurd-image-${{ hashFiles('scripts/download-image.sh') }}
    restore-keys: |
      hurd-image-

- name: Download image if not cached
  run: |
    if [ ! -f debian-hurd-amd64-20250807.qcow2 ]; then
      ./scripts/download-image.sh
    fi
```

### Pattern 4: Multi-Stage Testing

Build artifact, test it, then release:

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    outputs:
      image-tag: ${{ steps.meta.outputs.tags }}
    steps:
      - name: Build image
        run: docker build -t test-image .
      - name: Save image
        run: docker save test-image | gzip > image.tar.gz
      - name: Upload artifact
        uses: actions/upload-artifact@v4
        with:
          name: docker-image
          path: image.tar.gz

  test:
    needs: build
    runs-on: ubuntu-latest
    steps:
      - name: Download artifact
        uses: actions/download-artifact@v4
        with:
          name: docker-image
      - name: Load image
        run: docker load < image.tar.gz
      - name: Run tests
        run: |
          docker run test-image /tests/run-all.sh

  release:
    needs: [build, test]
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - name: Download artifact
        uses: actions/download-artifact@v4
      - name: Push to registry
        run: |
          docker load < image.tar.gz
          docker tag test-image ghcr.io/${{ github.repository }}:latest
          docker push ghcr.io/${{ github.repository }}:latest
```

### Pattern 5: Serial Console Automation

Interact with VM via serial console:

```yaml
- name: Start VM with serial console
  run: |
    docker-compose up -d
    # Serial console exposed on port 5555

- name: Wait for boot via serial log
  run: |
    timeout 300 bash -c '
      while ! docker exec hurd-x86_64 grep -q "login:" /tmp/serial.log; do
        echo "Waiting for boot..."
        sleep 5
      done
    '

- name: Login via serial (expect)
  run: |
    docker exec hurd-x86_64 expect << 'EOF'
    spawn telnet localhost 5555
    expect "login:"
    send "root\r"
    expect "Password:"
    send "root\r"
    expect "#"
    send "uname -a\r"
    expect "#"
    send "exit\r"
    EOF
```

---

## Performance Optimization Patterns

### Pattern: Parallel Job Execution

```yaml
jobs:
  lint:
    runs-on: ubuntu-latest
    steps: [...]

  test-unit:
    runs-on: ubuntu-latest
    steps: [...]

  test-integration:
    runs-on: ubuntu-latest
    steps: [...]

  # All three jobs run in parallel
```

### Pattern: Early Termination

```yaml
strategy:
  fail-fast: true  # Stop all jobs if one fails
  matrix:
    test: [unit, integration, e2e]
```

### Pattern: Conditional Job Execution

```yaml
jobs:
  expensive-test:
    # Only run on main branch or version tags
    if: github.ref == 'refs/heads/main' || startsWith(github.ref, 'refs/tags/v')
    runs-on: ubuntu-latest
    steps: [...]
```

---

## Security Best Practices

### Secret Management

```yaml
- name: Use secrets safely
  env:
    SSH_KEY: ${{ secrets.HURD_SSH_KEY }}
    PASSWORD: ${{ secrets.HURD_PASSWORD }}
  run: |
    # Secrets are masked in logs
    echo "$SSH_KEY" > ~/.ssh/id_rsa
    chmod 600 ~/.ssh/id_rsa
    # DON'T: echo "$PASSWORD"  # This would expose it
```

### Least Privilege Permissions

```yaml
permissions:
  contents: read       # Read repository
  packages: write      # Push to ghcr.io
  attestations: write  # Create attestations
  # Don't grant: issues, pull-requests, etc. unless needed
```

### Dependency Pinning

```yaml
steps:
  # Pin to major version (auto-updates)
  - uses: actions/checkout@v4

  # Pin to exact SHA (maximum security)
  - uses: actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11

  # Pin to specific version
  - uses: actions/setup-python@v4.7.1
```

---

## Troubleshooting Workflows

### Debug with tmate

Interactive debugging in CI:

```yaml
- name: Setup tmate session
  if: failure()
  uses: mxschmitt/action-tmate@v3
  timeout-minutes: 15
```

### Enhanced Logging

```yaml
- name: Debug workflow
  run: |
    echo "::group::System Info"
    uname -a
    docker --version
    echo "::endgroup::"

    echo "::group::Environment"
    env | sort
    echo "::endgroup::"

    echo "::group::Docker Containers"
    docker ps -a
    echo "::endgroup::"
```

### Artifacts for Debugging

```yaml
- name: Collect debug artifacts
  if: always()
  run: |
    mkdir -p debug
    docker-compose logs > debug/docker-logs.txt
    docker cp hurd-x86_64:/tmp/serial.log debug/ || true
    tar czf debug.tar.gz debug/

- name: Upload debug artifacts
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: debug-artifacts-${{ github.run_id }}
    path: debug.tar.gz
    retention-days: 7
```

---

## Example: Complete Test Workflow

```yaml
name: Comprehensive Test

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

env:
  QEMU_RAM: 4096
  QEMU_SMP: 2

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: shellcheck scripts/*.sh
      - run: yamllint .github/workflows/*.yml

  build-image:
    needs: validate
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Cache Hurd image
        uses: actions/cache@v3
        with:
          path: debian-hurd-amd64-*.qcow2
          key: hurd-${{ hashFiles('scripts/download-image.sh') }}

      - name: Download image
        run: ./scripts/download-image.sh || true

      - name: Build Docker image
        run: docker build -t test-image .

      - name: Save for next job
        run: |
          docker save test-image | gzip > image.tar.gz

      - uses: actions/upload-artifact@v4
        with:
          name: docker-image
          path: image.tar.gz

  test:
    needs: build-image
    runs-on: ubuntu-latest
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4

      - uses: actions/download-artifact@v4
        with:
          name: docker-image

      - name: Load image
        run: docker load < image.tar.gz

      - name: Start VM
        run: docker-compose up -d

      - name: Wait for SSH
        run: |
          for i in {1..120}; do
            if ssh -o StrictHostKeyChecking=no -p 2222 root@localhost true 2>/dev/null; then
              echo "SSH ready"
              exit 0
            fi
            sleep 5
          done
          exit 1

      - name: Run tests
        run: |
          ssh -p 2222 root@localhost << 'EOF'
          uname -a
          gcc --version
          make --version
          EOF

      - name: Cleanup
        if: always()
        run: docker-compose down

      - name: Upload logs
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: test-logs
          path: |
            *.log
            *.txt
```

---

## Reference

### Common QMP Commands

```json
{"execute":"query-status"}           // VM running?
{"execute":"query-cpus-fast"}        // CPU info
{"execute":"query-block"}            // Disk devices
{"execute":"stop"}                   // Pause VM
{"execute":"cont"}                   // Resume VM
{"execute":"system_powerdown"}       // ACPI shutdown
{"execute":"system_reset"}           // Reboot
{"execute":"human-monitor-command","arguments":{"command-line":"sendkey ret"}}
```

### Workflow Triggers

```yaml
on:
  push:                              # Any push
  pull_request:                      # Any PR
  workflow_dispatch:                 # Manual trigger
  schedule:                          # Cron schedule
    - cron: '0 2 * * *'             # Daily at 2 AM
  release:                           # Release created
    types: [created, published]
  workflow_run:                      # After another workflow
    workflows: ["Build"]
    types: [completed]
```

### Useful Actions

- `actions/checkout@v4` - Checkout code
- `actions/upload-artifact@v4` - Upload artifacts
- `actions/download-artifact@v4` - Download artifacts
- `actions/cache@v3` - Cache dependencies
- `docker/setup-buildx-action@v3` - Docker Buildx
- `docker/login-action@v3` - Registry login
- `docker/metadata-action@v5` - Extract metadata

---

**Status**: Production Ready (x86_64-only)
**Last Updated**: 2025-11-07
**Architecture**: Pure x86_64
