# Multi-Platform Debian GNU/Hurd QEMU Docker Image
# =============================================================================
# DESIGN PHILOSOPHY:
# - GNU/Hurd runs on x86_64 only (emulated via QEMU)
# - Container can run on amd64 OR arm64 hosts (multi-platform support)
# - Ubuntu 24.04 LTS base for stability and modern tooling
# - Minimal attack surface - only essential packages
# - Smart KVM detection with graceful TCG fallback
# - Production-ready with proper health monitoring
# =============================================================================

FROM ubuntu:24.04

# OCI labels for GHCR metadata and container registry
LABEL org.opencontainers.image.source="https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker"
LABEL org.opencontainers.image.description="Multi-platform GNU/Hurd x86_64 QEMU environment (runs on amd64 and arm64 hosts)"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.authors="x86_64-hurd-team"
LABEL qemu.binary="/usr/bin/qemu-system-x86_64"
LABEL qemu.guest.architecture="x86_64"
LABEL container.platforms="linux/amd64,linux/arm64"

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Multi-platform support - container runs on amd64 or arm64, QEMU emulates x86_64
# Note: GNU/Hurd itself only runs on x86_64 (via QEMU emulation)
RUN ARCH=$(dpkg --print-architecture) && \
    echo "Building for container architecture: $ARCH" && \
    echo "QEMU will emulate x86_64 for GNU/Hurd guest" && \
    if [ "$ARCH" != "amd64" ] && [ "$ARCH" != "arm64" ]; then \
      echo "ERROR: This Dockerfile supports amd64 and arm64 hosts only" && exit 1; \
    fi

# Update and install ONLY x86_64 packages
# WHY each package:
# - qemu-system-x86: x86_64 emulation (includes qemu-system-x86_64 binary)
# - qemu-utils: QCOW2 image management and conversion tools
# - curl/wget: Download Hurd images and health checks
# - ca-certificates: HTTPS certificate validation
# - socat: Advanced socket relay (better than netcat for port forwarding)
# - netcat-openbsd: Network connectivity testing
# - screen/tmux: Session management for interactive debugging
# - expect: Automated interaction with QEMU monitor
# - sshpass: Automated SSH for provisioning (optional)
# - iproute2: Advanced network configuration
# - procps: Process monitoring (ps, top)
# hadolint ignore=DL3008
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        qemu-system-x86 \
        qemu-utils \
        curl \
        wget \
        ca-certificates \
        socat \
        netcat-openbsd \
        screen \
        tmux \
        expect \
        sshpass \
        iproute2 \
        procps \
        && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Verify x86_64 QEMU binary exists with correct name
# CRITICAL: Debian package provides /usr/bin/qemu-system-x86_64 (with underscore!)
RUN test -x /usr/bin/qemu-system-x86_64 || \
    (echo "ERROR: qemu-system-x86_64 binary not found" && exit 1)

# Verify NO i386 contamination
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN ! dpkg --get-selections | grep -E ':i386|i386-' || \
    (echo "ERROR: i386 packages detected - this must be x86_64-only" && exit 1)

# Create directory structure
# WHY this layout:
# - /opt/hurd-image: VM disk images (matches existing repo structure)
# - /opt/scripts: Helper scripts and utilities
# - /var/log/qemu: QEMU output and debugging logs (FHS compliant)
RUN mkdir -p /opt/hurd-image /opt/scripts /var/log/qemu

# Create non-root user for security (best practice)
# Try UID/GID 1000 (typical first user), fall back to 1001 if taken
# CRITICAL: Must verify user creation succeeds (no silent failures with || true)
RUN if id -u 1000 >/dev/null 2>&1; then \
      HURD_UID=1001; HURD_GID=1001; \
    else \
      HURD_UID=1000; HURD_GID=1000; \
    fi && \
    groupadd -g $HURD_GID hurd && \
    useradd -l -u $HURD_UID -g $HURD_GID -m -s /bin/bash hurd && \
    chown -R hurd:hurd /opt/hurd-image /opt/scripts /var/log/qemu

# Copy entrypoint script with proper permissions
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Copy scripts directory (including health-check and all library dependencies)
# This ensures health-check.sh can source its required lib files
COPY scripts/ /opt/scripts/
RUN find /opt/scripts -type f -name "*.sh" -exec chmod +x {} \;

# Expose ports for container->host mapping
# 2222: SSH to Hurd guest (forwards to guest port 22)
# 8080: HTTP to Hurd guest (forwards to guest port 80)
# 5900: VNC display :0 (optional, for GUI debugging)
# 9999: QEMU monitor (for debugging and control)
EXPOSE 2222 8080 5900 9999

# Volume mount point for persistent VM images
VOLUME ["/opt/hurd-image"]

# Health check configuration
# WHY these timings:
# - interval=30s: Check every 30 seconds (Hurd boot can be slow)
# - timeout=10s: Allow time for network checks
# - start-period=180s: Give VM 3 minutes to boot initially
# - retries=3: Allow 3 failures before marking unhealthy
HEALTHCHECK --interval=30s --timeout=10s --start-period=180s --retries=3 \
    CMD /opt/scripts/health-check.sh || exit 1

# Switch to non-root user for security (runs QEMU as hurd:hurd)
USER hurd

# Default entrypoint - launches QEMU with smart KVM/TCG detection
ENTRYPOINT ["/entrypoint.sh"]

# No default CMD - all args handled in entrypoint
CMD []