# Pure x86_64-only Debian GNU/Hurd QEMU Docker Image
# =============================================================================
# DESIGN PHILOSOPHY:
# - ZERO i386 support - this is a pure x86_64 implementation
# - Ubuntu 24.04 LTS base for stability and modern tooling
# - Minimal attack surface - only essential packages
# - Smart KVM detection with graceful TCG fallback
# - Production-ready with proper health monitoring
# =============================================================================

FROM ubuntu:24.04

# OCI labels for GHCR metadata and container registry
LABEL org.opencontainers.image.source="https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker"
LABEL org.opencontainers.image.description="Pure x86_64 GNU/Hurd microkernel QEMU environment - NO i386"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.authors="x86_64-hurd-team"
LABEL org.opencontainers.image.architecture="x86_64"
LABEL qemu.binary="/usr/bin/qemu-system-x86_64"

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Architecture enforcement - FAIL FAST if not x86_64
RUN [ "$(dpkg --print-architecture)" = "amd64" ] || \
    (echo "ERROR: This Dockerfile requires x86_64/amd64 architecture" && exit 1)

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
RUN ! dpkg --get-selections | grep -E ':i386|i386-' || \
    (echo "ERROR: i386 packages detected - this must be x86_64-only" && exit 1)

# Create directory structure
# WHY this layout:
# - /opt/hurd-image: VM disk images (matches existing repo structure)
# - /opt/scripts: Helper scripts and utilities
# - /var/log/qemu: QEMU output and debugging logs (FHS compliant)
RUN mkdir -p /opt/hurd-image /opt/scripts /var/log/qemu

# Create non-root user for security (best practice)
# UID/GID 1000 matches typical first user on host for volume permissions
RUN groupadd -g 1000 hurd 2>/dev/null || true && \
    useradd -u 1000 -g 1000 -m -s /bin/bash hurd 2>/dev/null || true && \
    chown -R 1000:1000 /opt/hurd-image /opt/scripts /var/log/qemu

# Copy entrypoint script with proper permissions
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Copy health check script
COPY scripts/health-check.sh /opt/scripts/health-check.sh
RUN chmod +x /opt/scripts/health-check.sh

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