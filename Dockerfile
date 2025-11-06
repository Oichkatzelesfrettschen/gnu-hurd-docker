FROM debian:bookworm

# OCI labels for GHCR metadata
LABEL org.opencontainers.image.source="https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker"
LABEL org.opencontainers.image.description="GNU/Hurd i386 microkernel development environment with QEMU"
LABEL org.opencontainers.image.licenses="MIT"

RUN apt-get update && apt-get install -y \
    qemu-system-i386 \
    qemu-utils \
    screen \
    telnet \
    curl \
    socat \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/hurd-image

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 9999

ENTRYPOINT ["/entrypoint.sh"]
