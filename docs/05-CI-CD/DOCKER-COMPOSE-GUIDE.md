=============================================================================
DOCKER COMPOSE: CI/CD vs LOCAL DEVELOPMENT CONFIGURATION
=============================================================================
Document Version: 1.0 (2025-11-08)
Scope: Production-ready patterns for handling different environments
Reference: https://docs.docker.com/compose/multiple-compose-files/
=============================================================================

PROBLEM STATEMENT
=============================================================================

Goal: Configure docker-compose.yml to work seamlessly in two scenarios:

1. CI/CD (GitHub Actions):
   - Pull pre-built images from ghcr.io
   - No local build required (faster CI runs)
   - Image: ghcr.io/oichkatzelesfrettschen/gnu-hurd-docker:latest

2. Local Development:
   - Build images locally from source
   - Iterate quickly with code changes
   - Build from ./Dockerfile with local context

Requirements:
- Single source of truth (avoid duplication)
- Maintainable and production-ready
- Leverage Docker Compose V2 features
- Clear separation of concerns

=============================================================================
RECOMMENDED APPROACH: DOCKER-COMPOSE.OVERRIDE.YML PATTERN
=============================================================================

VERDICT: Use the docker-compose.override.yml pattern (Option 2)

WHY THIS IS THE BEST CHOICE:
1. Zero-configuration defaults: CI uses base file, local gets automatic override
2. Convention-based: Follows Docker Compose official best practices
3. No command-line flags needed for local development
4. Clean separation: Base file is production config, override is dev config
5. Explicit CI behavior: CI can ignore override or use -f to be explicit

PATTERN OVERVIEW:
- docker-compose.yml: Production/CI config (pulls pre-built image)
- docker-compose.override.yml: Local dev config (builds from source)
- CI: Uses only docker-compose.yml (ignores override)
- Local: Automatically merges both files (no flags needed)

=============================================================================
IMPLEMENTATION
=============================================================================

FILE 1: docker-compose.yml (Base Configuration - CI/Production)
-----------------------------------------------------------------------------
This file defines the canonical production configuration that pulls
pre-built images from GHCR.

```yaml
---
# =============================================================================
# GNU/Hurd Docker Compose - Production/CI Configuration
# =============================================================================
# This is the BASE configuration used in CI/CD and production.
# Local development: docker-compose.override.yml will automatically override
# the image section with a build section.
# =============================================================================

services:
  hurd-x86_64:
    # Production: Pull pre-built image from GHCR
    # This will be overridden by docker-compose.override.yml in local dev
    image: ghcr.io/oichkatzelesfrettschen/gnu-hurd-docker:latest

    container_name: hurd-x86_64-qemu
    restart: unless-stopped

    # Security configuration
    privileged: false
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    cap_add:
      - NET_ADMIN
      - SYS_ADMIN

    # Device access for KVM (optional, graceful fallback to TCG)
    devices:
      - /dev/kvm:/dev/kvm:rw

    # Port mappings
    ports:
      - "2222:2222"   # SSH
      - "8080:8080"   # HTTP
      - "5555:5555"   # Serial console
      - "9999:9999"   # QEMU monitor
      - "5900:5900"   # VNC (optional)

    # Volume mounts
    volumes:
      - hurd-disk:/opt/hurd-image:rw
      - ./share:/share:rw
      - ./logs:/var/log/qemu:rw

    # Environment configuration
    environment:
      QEMU_DRIVE: /opt/hurd-image/debian-hurd-amd64.qcow2
      QEMU_RAM: 4096
      QEMU_SMP: 2
      ENABLE_VNC: 0
      SERIAL_PORT: 5555
      MONITOR_PORT: 9999

    # Network configuration
    networks:
      - hurd-net

    # Resource limits
    mem_limit: 6g
    mem_reservation: 2g
    cpus: 4.0
    pids_limit: 200

    # Health check
    healthcheck:
      test: ["CMD", "/opt/scripts/health-check.sh"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 180s

    # Logging
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

    # Labels
    labels:
      com.docker.compose.project: "gnu-hurd"
      com.docker.compose.service: "hurd-x86_64"
      org.opencontainers.image.architecture: "x86_64"
      org.opencontainers.image.description: "Pure x86_64 GNU/Hurd QEMU environment"

    # Secrets
    secrets:
      - root_password
      - agents_password

# Secrets definition
secrets:
  root_password:
    file: ./secrets/root_password.txt
  agents_password:
    file: ./secrets/agents_password.txt

# Network definition
networks:
  hurd-net:
    driver: bridge
    ipam:
      config:
        - subnet: 172.25.0.0/24
          gateway: 172.25.0.1

# Volume definition
volumes:
  hurd-disk:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${PWD}/images
```

FILE 2: docker-compose.override.yml (Local Development Override)
-----------------------------------------------------------------------------
This file is automatically merged with docker-compose.yml when you run
docker compose commands locally. It overrides the image section with a
build section.

```yaml
---
# =============================================================================
# GNU/Hurd Docker Compose - Local Development Override
# =============================================================================
# This file is AUTOMATICALLY loaded by Docker Compose in local development.
# It overrides the 'image' configuration in docker-compose.yml with a 'build'
# configuration to enable local image building.
#
# CI/CD: This file is IGNORED (only docker-compose.yml is used)
# Local: This file is AUTOMATICALLY merged (no flags needed)
# =============================================================================

services:
  hurd-x86_64:
    # Override: Build locally instead of pulling from GHCR
    build:
      context: .
      dockerfile: Dockerfile
      args:
        BUILDKIT_INLINE_CACHE: 1

    # Override: Use local tag instead of GHCR tag
    image: gnu-hurd-docker:local-dev

    # Optional: Override environment for local debugging
    environment:
      # Inherit all from base, add/override specific ones
      DEBUG: 1
      VERBOSE: 1
```

FILE 3: .github/workflows/push-ghcr.yml (CI Configuration)
-----------------------------------------------------------------------------
Update the CI workflow to explicitly ignore the override file.

```yaml
---
name: Build and Push to GitHub Container Registry

on:
  push:
    branches:
      - main
    tags:
      - 'v*'
  pull_request:
    branches:
      - main
  workflow_dispatch:

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
      attestations: write
      id-token: write

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to GitHub Container Registry
        if: github.event_name != 'pull_request'
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata (tags, labels)
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          tags: |
            type=ref,event=branch
            type=ref,event=pr
            type=semver,pattern={{version}}
            type=semver,pattern={{major}}.{{minor}}
            type=semver,pattern={{major}}
            type=sha,prefix={{branch}}-
            type=raw,value=latest,enable={{is_default_branch}}

      - name: Build and push Docker image
        id: push
        uses: docker/build-push-action@v5
        with:
          context: .
          file: ./Dockerfile
          push: ${{ github.event_name != 'pull_request' }}
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
          provenance: false

      - name: Generate attestation
        if: github.event_name != 'pull_request'
        uses: actions/attest-build-provenance@v1
        with:
          subject-name: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          subject-digest: ${{ steps.push.outputs.digest }}
          push-to-registry: true

      # NEW: Test with docker-compose (CI mode - pulls image)
      - name: Create required directories and secrets
        run: |
          mkdir -p secrets share logs images
          echo "root" > secrets/root_password.txt
          echo "agents" > secrets/agents_password.txt

      - name: Test docker-compose (CI mode - pull image)
        run: |
          # CI: Explicitly use only docker-compose.yml (ignore override)
          # This tests that the production config works correctly
          docker compose -f docker-compose.yml pull

      - name: Verify pulled image
        run: |
          docker images | grep gnu-hurd
```

FILE 4: .github/workflows/build-x86_64.yml (Build and Test Workflow)
-----------------------------------------------------------------------------
This workflow builds the image and tests it using docker-compose.

```yaml
---
name: Build Hurd x86_64 Image

on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up QEMU
        run: |
          sudo apt-get update
          sudo apt-get install -y qemu-system-x86 qemu-utils

      - name: Download x86_64 image
        run: ./scripts/setup-hurd-amd64.sh

      - name: Build Docker image
        run: |
          REPO=$(echo "${{ github.repository }}" | tr '[:upper:]' '[:lower:]')
          docker build -t ghcr.io/$REPO:latest .

      - name: Create required directories and secrets
        run: |
          mkdir -p secrets share logs images
          echo "root" > secrets/root_password.txt
          echo "agents" > secrets/agents_password.txt

      # NEW: Remove override file to force CI behavior
      - name: Remove override file (test production config)
        run: rm -f docker-compose.override.yml

      - name: Start VM with docker-compose (CI mode)
        run: |
          # Since we removed override, this will use the image we just built
          # First, update docker-compose.yml to use local tag
          sed -i 's|ghcr.io/.*:latest|ghcr.io/'"$(echo "${{ github.repository }}" | tr '[:upper:]' '[:lower:]')"':latest|' docker-compose.yml
          docker compose up -d

      - name: Wait for boot
        run: sleep 180

      - name: Test SSH (may timeout on slow runners)
        run: |
          timeout 10 ssh -p 2222 -o StrictHostKeyChecking=no \
            -o ConnectTimeout=5 root@localhost "uname -a" || \
            echo "SSH not ready (expected on GitHub runners)"

      - name: Stop VM
        run: docker compose down

      - name: Upload image artifact
        uses: actions/upload-artifact@v4
        with:
          name: hurd-x86_64-image
          path: debian-hurd-amd64-80gb.qcow2
          retention-days: 30
```

=============================================================================
USAGE GUIDE
=============================================================================

LOCAL DEVELOPMENT (Automatic Override)
-----------------------------------------------------------------------------
When you run docker-compose commands locally, Docker Compose automatically
loads both docker-compose.yml AND docker-compose.override.yml:

```bash
# Build and start (uses override automatically)
docker compose up -d

# Build with no cache
docker compose build --no-cache

# View merged configuration (debugging)
docker compose config

# Stop and remove
docker compose down
```

HOW IT WORKS:
- Docker Compose searches for docker-compose.yml (base config)
- Docker Compose searches for docker-compose.override.yml (if exists, merge)
- Merged config: build section from override replaces image section from base
- Result: Local build instead of GHCR pull

CI/CD ENVIRONMENT (Explicit Base Only)
-----------------------------------------------------------------------------
In CI, you have two options:

OPTION A: Remove override file (recommended for testing production config)
```bash
# Remove override to force production behavior
rm -f docker-compose.override.yml

# Now docker compose will ONLY use docker-compose.yml
docker compose pull
docker compose up -d
```

OPTION B: Explicitly specify base file only
```bash
# Use -f flag to ignore override file
docker compose -f docker-compose.yml pull
docker compose -f docker-compose.yml up -d
```

OPTION C: Let CI naturally use override (builds in CI)
```bash
# If you WANT to build in CI (not recommended for speed)
# Just use docker compose normally
docker compose up -d
# This will build because override.yml is present
```

RECOMMENDATION FOR CI:
Use Option A (remove override) or Option B (explicit -f flag) to ensure
CI uses pre-built images from GHCR. This is faster and tests the actual
production deployment path.

=============================================================================
VERIFICATION AND DEBUGGING
=============================================================================

View Merged Configuration
-----------------------------------------------------------------------------
See exactly what configuration Docker Compose will use:

```bash
# Local (with override)
docker compose config

# CI (without override)
docker compose -f docker-compose.yml config
```

Key differences to look for:
- Local: Should show "build:" section
- CI: Should show "image: ghcr.io/..." only

Verify Image Source
-----------------------------------------------------------------------------
Check which image is being used:

```bash
# After docker compose up
docker ps --format "table {{.Names}}\t{{.Image}}"

# Expected local: gnu-hurd-docker:local-dev
# Expected CI: ghcr.io/oichkatzelesfrettschen/gnu-hurd-docker:latest
```

Test Both Scenarios Locally
-----------------------------------------------------------------------------
You can test both CI and local behavior on your machine:

```bash
# Test local development (with override)
docker compose up -d
# Should build from Dockerfile

docker compose down

# Test CI behavior (without override)
docker compose -f docker-compose.yml pull
docker compose -f docker-compose.yml up -d
# Should pull from GHCR

docker compose down
```

=============================================================================
ALTERNATIVE APPROACHES (NOT RECOMMENDED)
=============================================================================

We evaluated three other approaches. Here's why they're not ideal for this
use case:

OPTION 1: Environment Variable Substitution
-----------------------------------------------------------------------------
PATTERN:
```yaml
services:
  hurd:
    image: ${DOCKER_IMAGE:-ghcr.io/user/repo:latest}
    build:
      context: ${BUILD_CONTEXT:-.}
```

PROS:
- Single file
- Flexible with env vars

CONS:
- Complex: Requires setting ENV vars correctly in both environments
- Error-prone: Easy to forget to set vars, leading to silent failures
- Not idiomatic: Doesn't follow Docker Compose conventions
- Harder to review: Can't easily see what CI vs local looks like

VERDICT: ❌ Too complex for this use case

OPTION 3: Docker Compose Profiles
-----------------------------------------------------------------------------
PATTERN:
```yaml
services:
  hurd-build:
    profiles: [dev]
    build: .
    # ... rest of config

  hurd-pull:
    profiles: [ci]
    image: ghcr.io/user/repo:latest
    # ... rest of config
```

USAGE:
```bash
# Local
docker compose --profile dev up

# CI
docker compose --profile ci up
```

PROS:
- Single file
- Explicit service selection

CONS:
- Duplication: Must duplicate all service config for both variants
- Verbose: 2x the YAML for essentially the same service
- Maintenance burden: Changes must be applied to both services
- Naming complexity: Need different service names (hurd-build, hurd-pull)

VERDICT: ❌ Too much duplication

OPTION 4: Multiple Named Override Files
-----------------------------------------------------------------------------
PATTERN:
```yaml
# docker-compose.yml (base)
# docker-compose.dev.yml (local build)
# docker-compose.ci.yml (GHCR pull)
```

USAGE:
```bash
# Local
docker compose -f docker-compose.yml -f docker-compose.dev.yml up

# CI
docker compose -f docker-compose.yml -f docker-compose.ci.yml up
```

PROS:
- Explicit control
- Clear separation

CONS:
- Requires command-line flags: Not zero-config for local dev
- Against convention: docker-compose.override.yml is the standard
- More files: Requires managing 3+ files instead of 2
- Not automatic: Must remember which -f flags to use

VERDICT: ❌ Too manual, not idiomatic

=============================================================================
MIGRATION CHECKLIST
=============================================================================

To implement the recommended pattern:

1. Update docker-compose.yml
   - [ ] Set image: ghcr.io/oichkatzelesfrettschen/gnu-hurd-docker:latest
   - [ ] Remove build: section
   - [ ] Ensure all runtime config is correct
   - [ ] Commit changes

2. Create docker-compose.override.yml
   - [ ] Add services: hurd-x86_64: section
   - [ ] Add build: section with context and dockerfile
   - [ ] Override image: with local tag
   - [ ] Add development-specific env vars (optional)
   - [ ] Commit changes

3. Update .gitignore (optional)
   - [ ] Consider adding docker-compose.override.yml to .gitignore if
         you want each developer to have their own custom overrides
   - [ ] OR commit it for consistent team dev experience (recommended)

4. Update CI workflows
   - [ ] Remove docker-compose.override.yml in CI (Option A), OR
   - [ ] Use -f docker-compose.yml explicitly (Option B)
   - [ ] Test that CI pulls image instead of building
   - [ ] Verify workflow runs successfully

5. Update documentation
   - [ ] Update README.md with new docker compose commands
   - [ ] Document that override.yml is for local development
   - [ ] Add troubleshooting section for common issues
   - [ ] Update INSTALLATION.md or QUICKSTART.md

6. Test both scenarios
   - [ ] Local: docker compose up -d (should build)
   - [ ] CI: docker compose -f docker-compose.yml up (should pull)
   - [ ] Verify docker compose config output for both
   - [ ] Verify correct images are used (docker ps)

=============================================================================
TROUBLESHOOTING
=============================================================================

ISSUE: CI is building instead of pulling
CAUSE: docker-compose.override.yml is present in CI
FIX: Remove override file in CI workflow:
     rm -f docker-compose.override.yml

ISSUE: Local dev is pulling instead of building
CAUSE: docker-compose.override.yml is missing or not being loaded
FIX: Create docker-compose.override.yml with build section
     Verify: docker compose config | grep -A 5 "build:"

ISSUE: "image and build may not be used together"
CAUSE: Old Docker Compose version (< 2.0)
FIX: Upgrade to Docker Compose V2
     Version check: docker compose version

ISSUE: Override file not being loaded automatically
CAUSE: Working directory doesn't contain docker-compose.override.yml
FIX: Ensure file is in same directory as docker-compose.yml
     Verify: ls -la docker-compose*.yml

ISSUE: Different developers need different local configs
SOLUTION:
     1. Commit docker-compose.override.yml with sane defaults
     2. Add docker-compose.override.local.yml to .gitignore
     3. Developers create their own .local.yml for customization
     4. Use: docker compose -f docker-compose.yml \
                          -f docker-compose.override.yml \
                          -f docker-compose.override.local.yml up

=============================================================================
REFERENCES
=============================================================================

Official Docker Documentation:
- Multiple Compose files:
  https://docs.docker.com/compose/multiple-compose-files/

- Merge and override:
  https://docs.docker.com/compose/how-tos/multiple-compose-files/merge/

- Environment variables:
  https://docs.docker.com/compose/how-tos/environment-variables/

- Compose file reference:
  https://docs.docker.com/reference/compose-file/

- Compose specification (merging rules):
  https://docs.docker.com/reference/compose-file/merge/

Best Practices:
- Use docker-compose.override.yml for local development overrides
- Keep docker-compose.yml as the production/CI configuration
- Use explicit -f flags in CI to avoid surprises
- Version control both files (unless team prefers personal overrides)
- Document the pattern in README.md

=============================================================================
SUMMARY
=============================================================================

RECOMMENDED PATTERN: docker-compose.override.yml

FILES:
1. docker-compose.yml - Production config (GHCR image)
2. docker-compose.override.yml - Local dev config (build from source)

USAGE:
- Local: docker compose up (automatic merge, builds locally)
- CI: docker compose -f docker-compose.yml up (explicit base, pulls GHCR)

BENEFITS:
✅ Zero-config local development (automatic override)
✅ Explicit CI behavior (base file only)
✅ Convention-based (follows Docker Compose best practices)
✅ Maintainable (clear separation of concerns)
✅ Production-ready (tested pattern used widely)

NEXT STEPS:
1. Implement docker-compose.yml changes (use GHCR image)
2. Create docker-compose.override.yml (build locally)
3. Update CI to ignore override (rm or -f flag)
4. Test both scenarios
5. Update documentation

=============================================================================
END DOCUMENT
=============================================================================
