# Advanced GitHub Actions Workflows for GNU/Hurd

**Last Updated**: 2025-11-16
**Purpose**: Advanced workflow configurations including VNC, interactive sessions, and MCP integration
**Audience**: DevOps engineers, CI/CD architects, automation developers

---

## Table of Contents

1. [Overview](#overview)
2. [Interactive VNC Workflow](#interactive-vnc-workflow)
3. [MCP-Enabled Testing Workflow](#mcp-enabled-testing-workflow)
4. [Multi-Architecture Testing](#multi-architecture-testing)
5. [Performance Benchmarking](#performance-benchmarking)
6. [Automated GUI Testing](#automated-gui-testing)
7. [Workflow Best Practices](#workflow-best-practices)
8. [References](#references)

---

## Overview

This document covers advanced GitHub Actions workflows for the GNU/Hurd Docker environment, including:

- **Interactive VNC Sessions**: Web-accessible Hurd instances
- **MCP Integration**: AI agent testing with Model Context Protocol
- **Automated Testing**: Comprehensive system and integration tests
- **Performance Monitoring**: Benchmark tracking across commits
- **GUI Testing**: Automated desktop environment validation

---

## Interactive VNC Workflow

### Purpose

Creates an on-demand, web-accessible Hurd instance for:
- Interactive debugging
- GUI application testing
- Demonstrations and tutorials
- Manual testing sessions

### File: `.github/workflows/interactive-vnc.yml`

```yaml
name: Interactive Hurd with VNC Access

on:
  workflow_dispatch:
    inputs:
      duration:
        description: 'Session duration in minutes'
        required: true
        default: '30'
        type: choice
        options: ['15', '30', '60', '120']
      enable_gui:
        description: 'Install GUI (LXDE)'
        required: true
        default: 'false'
        type: boolean

jobs:
  interactive-hurd:
    runs-on: ubuntu-latest
    timeout-minutes: ${{ fromJSON(github.event.inputs.duration) + 10 }}

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup VNC environment
        run: |
          sudo apt-get update
          sudo apt-get install -y qemu-system-x86 qemu-utils
          # ... (see full workflow file)

      - name: Enable VNC and noVNC
        run: |
          # Start Hurd with VNC enabled
          docker compose -f docker-compose.yml -f docker-compose.vnc.yml up -d

      - name: Keep session alive
        run: |
          # Keep alive for specified duration
          sleep $(( ${{ github.event.inputs.duration }} * 60 ))
```

### Access Methods

During the workflow run:

1. **SSH**: Via GitHub Actions logs, you can see the connection command
2. **VNC**: Would be accessible if running locally (GitHub Actions doesn't expose ports publicly)
3. **Serial Console**: Available via logs

### Use Cases

```bash
# Trigger manually from GitHub Actions UI:
# 1. Go to Actions tab
# 2. Select "Interactive Hurd with VNC Access"
# 3. Click "Run workflow"
# 4. Choose duration and GUI options
# 5. Monitor via logs
```

### Limitations

- GitHub Actions runners don't expose network ports publicly
- Suitable for debugging via logs and screenshots
- For true interactive access, use local Docker or self-hosted runners

### Enhancements for Self-Hosted Runners

```yaml
# For self-hosted runners with public access:
jobs:
  interactive-hurd:
    runs-on: self-hosted  # Your own machine

    steps:
      # ... existing steps ...

      - name: Expose noVNC via ngrok
        run: |
          # Download ngrok
          wget https://bin.equinox.io/c/4VmDzA7iaHb/ngrok-stable-linux-amd64.zip
          unzip ngrok-stable-linux-amd64.zip

          # Expose noVNC port
          ./ngrok http 6080 &

          # Get public URL
          sleep 5
          curl http://localhost:4040/api/tunnels | jq -r '.tunnels[0].public_url'
```

---

## MCP-Enabled Testing Workflow

### Purpose

Integrates Model Context Protocol for AI-assisted testing and validation.

### Architecture

```
GitHub Actions Runner
  |
  +-- Docker Container (Hurd)
  |     |
  |     +-- QEMU (Hurd VM)
  |
  +-- MCP Server (Filesystem)
  |     |
  |     +-- Access to shared volumes
  |
  +-- Claude/AI Agent
        |
        +-- Execute tests via MCP
        +-- Analyze results
        +-- Generate reports
```

### File: `.github/workflows/mcp-testing.yml`

```yaml
name: MCP-Enabled Comprehensive Testing

on:
  push:
    branches: [main, develop]
  pull_request:

jobs:
  mcp-tests:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup MCP server
        run: |
          # Install Docker MCP server
          npm install -g @modelcontextprotocol/server-filesystem

          # Configure MCP for Hurd environment
          cat > mcp-config.json <<'EOF'
          {
            "mcpServers": {
              "hurd-files": {
                "command": "npx",
                "args": ["-y", "@modelcontextprotocol/server-filesystem", "./share"],
                "env": {
                  "ALLOWED_PATHS": "./share:/tmp"
                }
              }
            }
          }
          EOF

      - name: Start Hurd environment
        run: |
          docker compose up -d
          ./scripts/wait-for-boot.sh

      - name: Run MCP-assisted tests
        run: |
          # Copy test suite to shared volume
          cp -r tests/ share/

          # Execute tests via SSH and collect results in share/
          ssh -p 2222 -o StrictHostKeyChecking=no root@localhost \
            "cd /share/tests && bash run-all-tests.sh"

      - name: MCP analysis
        uses: modelcontextprotocol/analyze-action@v1
        with:
          config-file: mcp-config.json
          analysis-type: test-results
          output-file: mcp-analysis-report.md

      - name: Upload results
        uses: actions/upload-artifact@v4
        with:
          name: mcp-test-results
          path: |
            share/test-results/
            mcp-analysis-report.md
```

### MCP Integration Benefits

1. **Intelligent Test Analysis**: AI analyzes test failures and suggests fixes
2. **Automated Documentation**: Generate test reports from results
3. **Code Review**: MCP servers can review code in Hurd environment
4. **Filesystem Operations**: AI can manipulate files via MCP filesystem server

### Example MCP Test Script

```bash
#!/bin/bash
# tests/run-all-tests.sh - MCP-enabled test suite

# Test categories
CATEGORIES=(
    "system"
    "network"
    "filesystem"
    "translators"
    "compilation"
)

RESULTS_DIR="/share/test-results"
mkdir -p "$RESULTS_DIR"

# Run each category
for category in "${CATEGORIES[@]}"; do
    echo "Running $category tests..."

    # Execute tests and save results
    bash "tests-${category}.sh" > "$RESULTS_DIR/${category}.log" 2>&1

    # Generate MCP-readable JSON summary
    cat > "$RESULTS_DIR/${category}.json" <<EOF
{
  "category": "$category",
  "timestamp": "$(date -Iseconds)",
  "status": "$?",
  "log_file": "${category}.log"
}
EOF
done

# Create master index for MCP
cat > "$RESULTS_DIR/index.json" <<EOF
{
  "test_run": "$(date -Iseconds)",
  "categories": [$(printf '"%s",' "${CATEGORIES[@]}" | sed 's/,$//')]
}
EOF
```

---

## Multi-Architecture Testing

### Purpose

Test Hurd across different CPU configurations and acceleration modes.

### Matrix Testing

```yaml
name: Multi-Configuration Testing

on: [push, pull_request]

jobs:
  test-matrix:
    runs-on: ubuntu-latest

    strategy:
      fail-fast: false
      matrix:
        cpu: [1, 2, 4]
        ram: [2048, 4096, 8192]
        acceleration: [kvm, tcg]
        exclude:
          # Exclude TCG with high CPU counts (too slow)
          - cpu: 4
            acceleration: tcg
          # Exclude low RAM with high CPU
          - cpu: 4
            ram: 2048

    name: Test CPU=${{ matrix.cpu }} RAM=${{ matrix.ram }} ACCEL=${{ matrix.acceleration }}

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Configure test environment
        run: |
          cat >> docker-compose.override.yml <<EOF
          services:
            hurd-x86_64:
              environment:
                QEMU_SMP: ${{ matrix.cpu }}
                QEMU_RAM: ${{ matrix.ram }}
          EOF

      - name: Start Hurd
        run: docker compose up -d

      - name: Run test suite
        run: |
          ./scripts/wait-for-boot.sh
          ./scripts/test-hurd-system.sh

      - name: Collect metrics
        run: |
          # Record boot time, performance metrics
          ssh -p 2222 root@localhost "uptime" > metrics.txt
          docker stats --no-stream hurd-x86_64-qemu >> metrics.txt

      - name: Upload metrics
        uses: actions/upload-artifact@v4
        with:
          name: metrics-cpu${{ matrix.cpu }}-ram${{ matrix.ram }}-${{ matrix.acceleration }}
          path: metrics.txt
```

---

## Performance Benchmarking

### Purpose

Track performance regression across commits.

### Benchmark Workflow

```yaml
name: Performance Benchmarking

on:
  push:
    branches: [main]
  schedule:
    - cron: '0 0 * * 0'  # Weekly on Sunday

jobs:
  benchmark:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Start Hurd
        run: |
          docker compose up -d
          ./scripts/wait-for-boot.sh

      - name: Run benchmarks
        run: |
          ssh -p 2222 root@localhost <<'EOF'
          # Install benchmark tools
          apt update
          apt install -y sysbench stress-ng

          # CPU benchmark
          sysbench cpu --threads=2 run > /tmp/bench-cpu.txt

          # Memory benchmark
          sysbench memory --memory-total-size=1G run > /tmp/bench-mem.txt

          # Disk I/O benchmark
          sysbench fileio --file-test-mode=seqwr --file-total-size=1G prepare
          sysbench fileio --file-test-mode=seqwr run > /tmp/bench-disk.txt
          sysbench fileio cleanup

          # Compilation benchmark (build GNU Hello)
          apt source hello
          cd hello-*/
          time make > /tmp/bench-compile.txt 2>&1
          EOF

      - name: Collect results
        run: |
          scp -P 2222 root@localhost:/tmp/bench-*.txt ./

      - name: Parse and store results
        run: |
          # Extract key metrics
          CPU_SCORE=$(grep "total time" bench-cpu.txt | awk '{print $3}')
          MEM_SCORE=$(grep "total time" bench-mem.txt | awk '{print $3}')

          # Create JSON report
          cat > benchmark-results.json <<EOF
          {
            "commit": "${{ github.sha }}",
            "date": "$(date -Iseconds)",
            "cpu_time": "$CPU_SCORE",
            "memory_time": "$MEM_SCORE"
          }
          EOF

      - name: Update benchmark history
        uses: benchmark-action/github-action-benchmark@v1
        with:
          tool: 'customBiggerIsBetter'
          output-file-path: benchmark-results.json
          github-token: ${{ secrets.GITHUB_TOKEN }}
          auto-push: true
```

---

## Automated GUI Testing

### Purpose

Test GUI applications and desktop environments.

### GUI Test Workflow

```yaml
name: GUI Testing with VNC

on:
  push:
    paths:
      - 'docs/04-OPERATION/GUI-SETUP.md'
      - 'scripts/install-gui-*'

jobs:
  gui-tests:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Start Hurd with VNC
        run: |
          docker compose -f docker-compose.yml -f docker-compose.vnc.yml up -d
          ./scripts/wait-for-boot.sh

      - name: Install GUI
        run: |
          ssh -p 2222 root@localhost bash -s < scripts/install-gui-lxde.sh

      - name: Take VNC screenshots
        run: |
          # Install VNC screenshot tool
          sudo apt-get install -y vncsnapshot

          # Wait for X11 to start
          sleep 60

          # Capture screenshots
          vncsnapshot -passwd <(echo hurdvnc) localhost:5900 screenshot-desktop.png

      - name: Test applications
        run: |
          ssh -p 2222 root@localhost <<'EOF'
          export DISPLAY=:0

          # Launch xterm and capture
          xterm -e "echo 'GUI Test OK' && sleep 5" &

          sleep 10

          # Verify X is running
          ps aux | grep X
          EOF

      - name: Upload screenshots
        uses: actions/upload-artifact@v4
        with:
          name: gui-test-screenshots
          path: '*.png'
```

---

## Workflow Best Practices

### 1. Resource Management

```yaml
# Always set timeouts
jobs:
  my-job:
    timeout-minutes: 30

    steps:
      - name: Step with timeout
        timeout-minutes: 10
        run: ./long-running-script.sh
```

### 2. Artifact Management

```yaml
# Organize artifacts by type and retention
- name: Upload test results
  uses: actions/upload-artifact@v4
  with:
    name: test-results-${{ github.run_id }}
    path: |
      test-results/
      logs/
    retention-days: 7  # Clean up after 1 week

- name: Upload build artifacts
  uses: actions/upload-artifact@v4
  with:
    name: hurd-image-${{ github.sha }}
    path: '*.qcow2'
    retention-days: 30  # Keep builds longer
```

### 3. Conditional Execution

```yaml
# Skip expensive steps on documentation-only changes
jobs:
  test:
    if: "!contains(github.event.head_commit.message, '[skip ci]')"

    steps:
      - name: Run tests
        if: contains(github.event.head_commit.modified, 'src/')
        run: ./test.sh
```

### 4. Caching

```yaml
# Cache QEMU images
- name: Cache Hurd image
  uses: actions/cache@v3
  with:
    path: |
      debian-hurd-amd64.qcow2
      ~/.cache/qemu
    key: hurd-image-${{ hashFiles('scripts/setup-hurd-amd64.sh') }}
    restore-keys: |
      hurd-image-
```

### 5. Secret Management

```yaml
# Use GitHub Secrets for credentials
- name: Configure credentials
  env:
    ROOT_PASSWORD: ${{ secrets.HURD_ROOT_PASSWORD }}
    AGENTS_PASSWORD: ${{ secrets.HURD_AGENTS_PASSWORD }}
  run: |
    echo "$ROOT_PASSWORD" > secrets/root_password.txt
    echo "$AGENTS_PASSWORD" > secrets/agents_password.txt
```

---

## Workflow Comparison

| Workflow | Duration | Resource Usage | Use Case |
|----------|----------|----------------|----------|
| **build-x86_64** | 5-10 min | Low | CI/CD builds |
| **interactive-vnc** | User-defined | Medium | Debugging, demos |
| **mcp-testing** | 15-20 min | Medium | AI-assisted testing |
| **performance** | 30-40 min | High | Benchmark tracking |
| **gui-tests** | 20-30 min | Medium | GUI validation |

---

## References

### GitHub Actions

- **Actions Documentation**: https://docs.github.com/en/actions
- **Workflow Syntax**: https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions
- **Matrix Builds**: https://docs.github.com/en/actions/using-jobs/using-a-matrix-for-your-jobs

### Docker Compose in CI/CD

- **Docker Compose**: https://docs.docker.com/compose/
- **Compose in CI**: https://docs.docker.com/compose/ci-cd/

### MCP Resources

- **Docker MCP**: https://docs.docker.com/ai/mcp-catalog-and-toolkit/
- **MCP Specification**: https://spec.modelcontextprotocol.io/

### Related Documentation

- [WORKFLOWS.md](WORKFLOWS.md) - Basic workflows
- [SETUP.md](SETUP.md) - CI/CD setup guide
- [../04-OPERATION/DOCKER-QEMU-CLI.md](../04-OPERATION/DOCKER-QEMU-CLI.md) - CLI interactions
- [PROVISIONED-IMAGE.md](PROVISIONED-IMAGE.md) - Pre-provisioned images

---

**Pro Tip**: Use `workflow_dispatch` for interactive workflows and `schedule` for automated performance tracking!
